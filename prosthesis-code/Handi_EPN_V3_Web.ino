/*
 * ============================================================================
 *  HANDI EPN V3 - VERSION SERVIDOR WEB (reemplaza Bluetooth)
 * ============================================================================
 *  Misma funcionalidad que Handi_EPN_V3_Bluetooth.ino, pero los comandos
 *  llegan por HTTP en lugar de BluetoothSerial.
 *
 *  RED:  AP + STA con fallback
 *        - Intenta conectarse a tu WiFi (STA_SSID / STA_PASS).
 *        - Siempre levanta su propio Access Point (AP_SSID / AP_PASS) para que
 *          la protesis sea accesible aunque no haya router.
 *        - mDNS: http://handi.local  (cuando esta en modo STA)
 *        - AP por defecto: http://192.168.4.1
 *
 *  API HTTP (REST):
 *    GET  /                 -> pagina de control embebida (PROGMEM)
 *    GET  /cmd?c=<comando>  -> ejecuta un comando (mismo formato que Bluetooth)
 *    POST /cmd              -> cuerpo = comando en texto plano
 *    GET  /status           -> JSON: encoders, targets, grados, wifi
 *    GET  /sensors          -> JSON: lectura de los 16 canales del MUX
 *    GET  /telemetry        -> trama "aJbJcJdJeJfJ0" (compat. App Inventor)
 *    GET  /info             -> JSON: ip, rssi, uptime, heap
 *
 *  COMANDOS (identicos a la version Bluetooth):
 *    Gestos:  S O G I R P W Y L M H U C X
 *    Ejes:    A<pos1>,B<pos2>,C<pos3>,D<pos4>,E<servo>,F<pos5>
 *             ej:  /cmd?c=A600,B450,C600,D400,E125,F100
 *
 *  Ejemplos:
 *    curl "http://192.168.4.1/cmd?c=C"
 *    curl "http://192.168.4.1/cmd?c=A600,B450,E125"
 *    curl -X POST --data "A0,B0,C0,D0,E0,F0" http://192.168.4.1/cmd
 * ============================================================================
 */

#include <Wire.h>
#include <Adafruit_MotorShield.h>
#include <ESP32Encoder.h>
#include <ESP32Servo.h>

// ---------- WEB (antes: BluetoothSerial.h) ----------
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>

// ====================== CONFIGURACION DE RED ======================
// Credenciales de TU router (modo estacion). Dejar vacio "" para saltar STA.
const char* STA_SSID = "MI_RED_WIFI";
const char* STA_PASS = "MI_CLAVE_WIFI";

// Access Point propio de la protesis (fallback / siempre disponible)
const char* AP_SSID  = "HANDI_EPN";
const char* AP_PASS  = "handi1234";   // minimo 8 caracteres, o "" para red abierta

const char* MDNS_NAME = "handi";      // -> http://handi.local

const unsigned long WIFI_TIMEOUT_MS   = 12000; // espera maxima para conectar a STA
const bool          AP_SIEMPRE_ACTIVO = true;  // true = AP encendido aunque STA conecte
// ==================================================================

WebServer server(80);
bool staConectado = false;

TaskHandle_t Nucleo1;
TaskHandle_t Nucleo2;

// Crear instancias de las shield
Adafruit_MotorShield AFMS1 = Adafruit_MotorShield(0x60);  // Direccion I2C por defecto - shield bot
Adafruit_MotorShield AFMS2 = Adafruit_MotorShield(0x61);  // Direccion I2C estaniada - shield top

// Variables para los motores y los encoders
Adafruit_DCMotor *motor1;
Adafruit_DCMotor *motor2;
Adafruit_DCMotor *motor3;
Adafruit_DCMotor *motor4;
Adafruit_DCMotor *motor5;

ESP32Encoder encoder1;
ESP32Encoder encoder2;
ESP32Encoder encoder3;
ESP32Encoder encoder4;
ESP32Encoder encoder5;

#define S0_PIN 33
#define S1_PIN 15
#define S2_PIN 2
#define S3_PIN 4
#define SIG_PIN 35   // ADC1 -> compatible con WiFi activo (NO usar pines ADC2)

Servo myServo;               // Crear un objeto Servo
const int servoPin = 13;     // Pin donde esta conectado el servomotor

// Pines del encoder
const int encoder1PinA = 27;
const int encoder1PinB = 14;
const int encoder2PinA = 25;
const int encoder2PinB = 26;
const int encoder3PinA = 16;
const int encoder3PinB = 17;
const int encoder4PinA = 18;
const int encoder4PinB = 19;
const int encoder5PinA = 5;
const int encoder5PinB = 23;

//estados del motor
int stateMotor1 = 0;
int stateMotor2 = 0;
int stateMotor3 = 0;
int stateMotor4 = 0;
int stateMotor5 = 0;

// Variables de posicion
long targetPos1 = 0;
long targetPos2 = 0;
long targetPos3 = 0;
long targetPos4 = 0;
long targetPos5 = 0;
int  targetServoPos = 0;     // Posicion objetivo del servomotor

//para bucle de impresion
unsigned long lastUpdateTime = 0;
unsigned long lastPrintTime = 0;
unsigned long lastUpdateTimeMux = 0;
const unsigned long updateInterval = 100;  // Intervalo de actualizacion en milisegundos
const unsigned long printInterval  = 500;  // Intervalo de impresion en milisegundos

// Parametros del controlador PI
const float Kp  = 0.25;  // Ganancia proporcional se debe ajustar segun el maximo error 400
const float Ki  = 0.05;
const float Kp1 = 0.5;
const float Kp4 = 0.5;
const float Kp3 = 0.25;

// Acumuladores de error para el termino integral - Suma de Riemann
float integral1 = 0;
float integral2 = 0;
float integral3 = 0;
float integral4 = 0;

long Encoder1Acond = 0;
long Encoder2Acond = 0;
long Encoder3Acond = 0;
long Encoder4Acond = 0;
long Encoder5Acond = 0;

// Variables para verificar el movimiento del encoder
long lastPos1 = 0;
long lastPos2 = 0;
long lastPos3 = 0;
long lastPos4 = 0;
long lastPos5 = 0;

unsigned long lastMuxUpdateTime = 0; //auxiliar
unsigned long CheckInterval = 10;    // Intervalo para verificar el movimiento en milisegundos
int currentMuxChannel = 0;
// Variables para lectura de datos
unsigned long waitTime = 500;        // Tiempo en milisegundos
unsigned long previousMicrosMux = 0;

// ---------------- WEB RX + Idle re-arm ----------------
// (equivalente a la logica anti-basura/anti-tirones de la version Bluetooth)
const size_t WEB_MAX_LINE = 80;                // longitud maxima aceptada de un comando

static unsigned long lastValidCmdMs = 0;
static bool idleArmed = false;
const unsigned long IDLE_ARM_MS = 30000;       // tras 30s sin comando valido, re-armar en el proximo

static int  lastClientCount = 0;               // clientes asociados al AP (detecta reconexiones)
static String lastTelemetry = "";              // ultima trama tipo App Inventor
// ------------------------------------------------------

enum InputSource { SERIAL_IN, WEB_IN };
InputSource currentSource = SERIAL_IN;

//Declaracion de funciones
void selectChannel(int channel);
void mux(unsigned long currentMicros);
void updateMotorPositions();
void parseAndSetTargetPositions(String input);
void stopMotors();
void moveToPositions(long position1, long position2, long position3, long position4, int servoPos, long position5);
void rearmAfterIdle();
bool isLikelyValidCommand(const String& sIn);
void setupWiFi();
void setupWebServer();
bool aplicarComandoWeb(const String& raw);
String buildTelemetry();
String buildStatusJson();
String buildSensorsJson();

//estructura de dato para lectura mux
typedef struct
{
  int MENIQUE_M;
  int MENIQUE_I;
  int ANULAR_M;
  int ANULAR_I;
  int MEDIO_M;
  int MEDIO_I;
  int INDICE_M;
  int INDICE_I;
  int PULGAR_M;
  int PULGAR_I;
  int PULGAR_In;
  int MENIQUE_F;
  int ANULAR_F;
  int MEDIO_F;
  int INDICE_F;
  int PULGAR_F;
} Estructura;
Estructura datos;

// ============================ PAGINA WEB ============================
// HTML embebido en PROGMEM (no requiere SPIFFS). Usa la misma API REST.
const char PAGINA_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html><html lang="es"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>HANDI EPN V3</title>
<style>
:root{--bg:#0e1117;--card:#171c26;--bd:#28303d;--fg:#e6edf3;--mut:#8b98a9;--ac:#3fb950;--dg:#f85149}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,Segoe UI,Roboto,sans-serif;padding:16px}
h1{font-size:19px;margin:0 0 4px}.sub{color:var(--mut);font-size:13px;margin-bottom:16px}
.card{background:var(--card);border:1px solid var(--bd);border-radius:10px;padding:14px;margin-bottom:14px}
h2{font-size:13px;text-transform:uppercase;letter-spacing:.06em;color:var(--mut);margin:0 0 10px}
.g{display:grid;grid-template-columns:repeat(auto-fill,minmax(104px,1fr));gap:8px}
button{background:#222b38;color:var(--fg);border:1px solid var(--bd);border-radius:8px;padding:10px 6px;font-size:14px;cursor:pointer}
button:active{background:#2e3a4b}
button.ac{border-color:var(--ac);color:var(--ac)}
button.dg{border-color:var(--dg);color:var(--dg)}
.row{display:grid;grid-template-columns:78px 1fr 52px;gap:10px;align-items:center;margin-bottom:9px}
.row label{font-size:13px;color:var(--mut)}
input[type=range]{width:100%;accent-color:var(--ac)}
.val{font-variant-numeric:tabular-nums;text-align:right;font-size:13px}
table{width:100%;border-collapse:collapse;font-size:13px}
td{padding:4px 0;border-bottom:1px solid var(--bd)}td:last-child{text-align:right;font-variant-numeric:tabular-nums}
#log{font-family:ui-monospace,Consolas,monospace;font-size:12px;color:var(--mut);white-space:pre-wrap;min-height:18px}
</style></head><body>
<h1>HANDI EPN V3</h1><div class="sub" id="net">Servidor web en ESP32</div>

<div class="card"><h2>Gestos</h2><div class="g">
<button class="dg" onclick="cmd('S')">STOP</button>
<button class="ac" onclick="cmd('O')">Abrir</button>
<button onclick="cmd('C')">Cerrar</button>
<button onclick="cmd('G')">Apuntar</button>
<button onclick="cmd('R')">Spiderman</button>
<button onclick="cmd('P')">OK</button>
<button onclick="cmd('W')">Garra</button>
<button onclick="cmd('Y')">Okay</button>
<button onclick="cmd('L')">Like</button>
<button onclick="cmd('M')">Call me</button>
<button onclick="cmd('H')">Tres</button>
<button onclick="cmd('U')">Cuatro</button>
<button onclick="cmd('X')">Calibrar (0)</button>
<button onclick="cmd('I')">Init shields</button>
</div></div>

<div class="card"><h2>Control manual</h2>
<div class="row"><label>M1 (A)</label><input type="range" id="A" min="0" max="700" value="0" oninput="sv('A')"><span class="val" id="vA">0</span></div>
<div class="row"><label>M2 (B)</label><input type="range" id="B" min="0" max="700" value="0" oninput="sv('B')"><span class="val" id="vB">0</span></div>
<div class="row"><label>M3 (C)</label><input type="range" id="C" min="0" max="700" value="0" oninput="sv('C')"><span class="val" id="vC">0</span></div>
<div class="row"><label>M4 (D)</label><input type="range" id="D" min="0" max="700" value="0" oninput="sv('D')"><span class="val" id="vD">0</span></div>
<div class="row"><label>Servo (E)</label><input type="range" id="E" min="0" max="180" value="0" oninput="sv('E')"><span class="val" id="vE">0</span></div>
<div class="row"><label>M5 (F)</label><input type="range" id="F" min="0" max="300" value="0" oninput="sv('F')"><span class="val" id="vF">0</span></div>
<button onclick="enviarTodo()">Enviar posiciones</button>
</div>

<div class="card"><h2>Estado</h2><table id="st"></table></div>
<div class="card"><h2>Consola</h2><div id="log">listo</div></div>

<script>
const log=t=>document.getElementById('log').textContent=t;
function cmd(c){fetch('/cmd?c='+encodeURIComponent(c)).then(r=>r.text()).then(t=>log('> '+c+'  ->  '+t)).catch(e=>log('error: '+e));}
function sv(id){document.getElementById('v'+id).textContent=document.getElementById(id).value;}
function enviarTodo(){
  const p=['A','B','C','D','E','F'].map(k=>k+document.getElementById(k).value).join(',');
  cmd(p);
}
function tick(){
  fetch('/status').then(r=>r.json()).then(d=>{
    document.getElementById('net').textContent=d.modo+'  |  '+d.ip;
    const f=(n,a,b)=>'<tr><td>'+n+'</td><td>'+a+' / '+b+'</td></tr>';
    document.getElementById('st').innerHTML=
      '<tr><td>motor</td><td>actual / objetivo</td></tr>'+
      f('M1',d.enc1,d.tgt1)+f('M2',d.enc2,d.tgt2)+f('M3',d.enc3,d.tgt3)+
      f('M4',d.enc4,d.tgt4)+f('M5',d.enc5,d.tgt5)+
      '<tr><td>Servo</td><td>'+d.servo+'</td></tr>';
  }).catch(()=>{});
}
setInterval(tick,600);tick();
</script></body></html>
)rawliteral";
// ====================================================================

void TareaNucleo2(void * pvParameters) {
  for (;;) {
    unsigned long currentMillis = millis();
    lastMuxUpdateTime = currentMillis;
    mux(currentMillis);
    vTaskDelay(10);  // Agregar un pequenio retardo para liberar el CPU
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);

  // -------- RED + SERVIDOR WEB (sustituye a SerialBT.begin) --------
  setupWiFi();
  setupWebServer();
  lastValidCmdMs = millis();
  // -----------------------------------------------------------------

  xTaskCreatePinnedToCore(TareaNucleo2, "Tarea2", 10000, NULL, 1, &Nucleo2, 0);

  // Inicializar las shield y los motores
  AFMS1.begin();
  AFMS2.begin();
  pinMode(S0_PIN, OUTPUT);
  pinMode(S1_PIN, OUTPUT);
  pinMode(S2_PIN, OUTPUT);
  pinMode(S3_PIN, OUTPUT);

  Serial.println("Motor shields initialized.");

  //Arriba M1 DEDO 5 M2 DEDO 2 M3 DEDO 3
  //dedo 5 seria el movimiento del pulgar
  //ABAJO M1 DEDO 1 M2 DEDO 4

  // Asignar los motores a las shield
  motor1 = AFMS1.getMotor(1);  // Motor 1 en la primera shield
  motor2 = AFMS2.getMotor(2);  // Motor 2 en la segunda shield
  motor3 = AFMS2.getMotor(3);  // Motor 3 en la segunda shield
  motor4 = AFMS1.getMotor(2);  // Motor 4 en la primera shield
  motor5 = AFMS2.getMotor(1);  // Motor 5 en la segunda shield
  Serial.println("Motors assigned.");

  // Configurar velocidad inicial de los motores
  motor1->setSpeed(50);
  motor2->setSpeed(50);
  motor3->setSpeed(50);
  motor4->setSpeed(50);
  motor5->setSpeed(50);

  // Inicializar los encoders
  ESP32Encoder::useInternalWeakPullResistors = puType::up;
  Serial.println("Initializing encoders...");

  encoder1.attachSingleEdge(encoder1PinA, encoder1PinB);
  encoder1.clearCount();
  encoder2.attachSingleEdge(encoder2PinA, encoder2PinB);
  encoder2.clearCount();
  encoder3.attachSingleEdge(encoder3PinA, encoder3PinB);
  encoder3.clearCount();
  encoder4.attachSingleEdge(encoder4PinA, encoder4PinB);
  encoder4.clearCount();
  encoder5.attachSingleEdge(encoder5PinA, encoder5PinB);
  encoder5.clearCount();

  Serial.println("Encoders initialized.");

  // Inicializar el servomotor
  myServo.attach(servoPin);
}

void loop() {
  // ---- Atender peticiones HTTP (no bloqueante) ----
  server.handleClient();

  // Comprobar si hay datos disponibles en Serial
  if (Serial.available() > 0) {
    currentSource = SERIAL_IN;
    String input = Serial.readStringUntil('\n');
    Serial.print("Serial input received: ");
    Serial.println(input);
    parseAndSetTargetPositions(input);
    lastValidCmdMs = millis();
    idleArmed = false;
  }

  // Detectar conexion/desconexion de clientes en el AP:
  // en las transiciones se re-arma para evitar tirones con comandos viejos
  int clientes = WiFi.softAPgetStationNum();
  if (clientes != lastClientCount) {
    lastClientCount = clientes;
    rearmAfterIdle();
    idleArmed = false;
  }

  // Si estuvimos demasiado tiempo inactivos, armar la rutina de re-arme
  unsigned long now = millis();
  if (!idleArmed && (now - lastValidCmdMs) > IDLE_ARM_MS) {
    idleArmed = true;
  }

  // Actualizar la posicion de los motores periodicamente sin bloquear el ciclo principal
  unsigned long currentMillis = millis();

  if (currentMillis - lastUpdateTime >= updateInterval) {
    lastUpdateTime = currentMillis;
    updateMotorPositions(); //actualizo la posicion de los motores
  }

  // Refrescar telemetria / imprimir cada cierto intervalo
  if (currentMillis - lastPrintTime >= printInterval) {
    lastPrintTime = currentMillis;
    Encoder1Acond = map(encoder1.getCount(), 0, 400, 0, 90);
    Encoder2Acond = map(encoder2.getCount(), 0, 400, 0, 90);
    Encoder3Acond = map(encoder3.getCount(), 0, 500, 0, 90);
    Encoder4Acond = map(encoder4.getCount(), 0, 400, 0, 90);
    Encoder5Acond = map(encoder5.getCount(), 0, 200, 0, 70);

    // Trama equivalente a la que se enviaba por Bluetooth a App Inventor.
    // Ahora se publica en el endpoint /telemetry en lugar de SerialBT.println()
    lastTelemetry = buildTelemetry();

    if (currentSource == SERIAL_IN) {
      Serial.print("Dato pulgar F: ");
      Serial.print(datos.PULGAR_F);
      Serial.print("\t Dato indice F: ");
      Serial.print(datos.INDICE_F);
      Serial.print("\t Dato medio F: ");
      Serial.print(datos.MEDIO_F);
      Serial.print("\t Dato anular F: ");
      Serial.print(datos.ANULAR_F);
      Serial.print("\t Dato menique F: ");
      Serial.print(datos.MENIQUE_F);
      Serial.print("\t Dato pulgar I: ");
      Serial.println(datos.PULGAR_I);
      Serial.print("\t Dato indice I: ");
      Serial.print(datos.INDICE_I);
      Serial.print("\t Dato medio I: ");
      Serial.print(datos.MEDIO_I);
      Serial.print("\t Dato anular I: ");
      Serial.print(datos.ANULAR_I);
      Serial.print("\t Dato menique I: ");
      Serial.print(datos.MENIQUE_I);
      Serial.print("\t Nucleo: ");
      Serial.println(xPortGetCoreID());

      Serial.print("Posicion Actual del Motor 1: ");
      Serial.print(encoder1.getCount());
      Serial.print("\t Motor 2: ");
      Serial.print(encoder2.getCount());
      Serial.print("\t Motor 3: ");
      Serial.println(encoder3.getCount());
      Serial.print("Posicion Actual del Motor 4: ");
      Serial.print(encoder4.getCount());
      Serial.print("\t Motor 5: ");
      Serial.print(encoder5.getCount());
      Serial.print("\t Servomotor: ");
      Serial.println(targetServoPos);
    }
  }
}

// ======================= RED / SERVIDOR WEB =======================

void setupWiFi() {
  WiFi.persistent(false);
  WiFi.mode(WIFI_AP_STA);

  // --- Intento de conexion a la red del usuario (STA) ---
  if (strlen(STA_SSID) > 0) {
    Serial.printf("Conectando a WiFi \"%s\" ...\n", STA_SSID);
    WiFi.begin(STA_SSID, STA_PASS);
    unsigned long t0 = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - t0) < WIFI_TIMEOUT_MS) {
      delay(250);
      Serial.print(".");
    }
    Serial.println();
    staConectado = (WiFi.status() == WL_CONNECTED);
  }

  if (staConectado) {
    Serial.print("Conectado. IP en la red: http://");
    Serial.println(WiFi.localIP());
  } else {
    Serial.println("No se pudo conectar al router -> se usara solo el AP propio.");
  }

  // --- Access Point propio (fallback, o siempre activo) ---
  if (!staConectado || AP_SIEMPRE_ACTIVO) {
    if (strlen(AP_PASS) >= 8) {
      WiFi.softAP(AP_SSID, AP_PASS);
    } else {
      WiFi.softAP(AP_SSID);   // red abierta si la clave es muy corta
    }
    Serial.print("AP \"");
    Serial.print(AP_SSID);
    Serial.print("\" activo. IP: http://");
    Serial.println(WiFi.softAPIP());
  } else {
    WiFi.mode(WIFI_STA);
  }

  // --- mDNS: http://handi.local ---
  if (MDNS.begin(MDNS_NAME)) {
    MDNS.addService("http", "tcp", 80);
    Serial.printf("mDNS activo: http://%s.local\n", MDNS_NAME);
  }

  WiFi.setSleep(false);   // menor latencia en los comandos
}

void enviarCORS() {
  server.sendHeader("Access-Control-Allow-Origin", "*");
  server.sendHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
}

void setupWebServer() {

  // Pagina de control
  server.on("/", HTTP_GET, []() {
    enviarCORS();
    server.send_P(200, "text/html", PAGINA_HTML);
  });

  // Comando por GET:  /cmd?c=A600,B450   |   /cmd?c=C
  server.on("/cmd", HTTP_GET, []() {
    enviarCORS();
    if (!server.hasArg("c")) {
      server.send(400, "text/plain", "ERR: falta parametro c");
      return;
    }
    String c = server.arg("c");
    if (aplicarComandoWeb(c)) {
      server.send(200, "text/plain", "OK " + c);
    } else {
      server.send(400, "text/plain", "ERR comando invalido: " + c);
    }
  });

  // Comando por POST: cuerpo en texto plano, o parametro c
  server.on("/cmd", HTTP_POST, []() {
    enviarCORS();
    String c = server.hasArg("plain") ? server.arg("plain") : server.arg("c");
    if (aplicarComandoWeb(c)) {
      server.send(200, "text/plain", "OK " + c);
    } else {
      server.send(400, "text/plain", "ERR comando invalido: " + c);
    }
  });

  server.on("/cmd", HTTP_OPTIONS, []() {
    enviarCORS();
    server.send(204);
  });

  // Estado completo en JSON
  server.on("/status", HTTP_GET, []() {
    enviarCORS();
    server.send(200, "application/json", buildStatusJson());
  });

  // Lectura del multiplexor (sensores de los dedos) en JSON
  server.on("/sensors", HTTP_GET, []() {
    enviarCORS();
    server.send(200, "application/json", buildSensorsJson());
  });

  // Trama compatible con la app de App Inventor: "g1Jg2Jg3Jg4JservoJg5J0"
  server.on("/telemetry", HTTP_GET, []() {
    enviarCORS();
    server.send(200, "text/plain", lastTelemetry.length() ? lastTelemetry : buildTelemetry());
  });

  // Informacion del dispositivo
  server.on("/info", HTTP_GET, []() {
    enviarCORS();
    String j = "{";
    j += "\"modo\":\"" + String(staConectado ? "STA+AP" : "AP") + "\",";
    j += "\"ip_sta\":\"" + (staConectado ? WiFi.localIP().toString() : String("-")) + "\",";
    j += "\"ip_ap\":\"" + WiFi.softAPIP().toString() + "\",";
    j += "\"rssi\":" + String(staConectado ? WiFi.RSSI() : 0) + ",";
    j += "\"clientes_ap\":" + String(WiFi.softAPgetStationNum()) + ",";
    j += "\"uptime_s\":" + String(millis() / 1000) + ",";
    j += "\"heap\":" + String(ESP.getFreeHeap());
    j += "}";
    server.send(200, "application/json", j);
  });

  server.onNotFound([]() {
    enviarCORS();
    server.send(404, "text/plain", "404: usar / , /cmd?c= , /status , /sensors , /telemetry , /info");
  });

  server.begin();
  Serial.println("Servidor HTTP iniciado en el puerto 80.");
}

// Aplica un comando recibido por HTTP, con las mismas protecciones que tenia
// la version Bluetooth (validacion de trama + re-arme tras inactividad).
bool aplicarComandoWeb(const String& raw) {
  String input = raw;
  input.trim();

  if (input.length() == 0 || input.length() > WEB_MAX_LINE) return false;
  if (!isLikelyValidCommand(input)) return false;

  currentSource = WEB_IN;

  // Si veniamos de un periodo de inactividad, re-armar ANTES de aplicar
  if (idleArmed) {
    rearmAfterIdle();
    idleArmed = false;
  }

  parseAndSetTargetPositions(input);
  lastValidCmdMs = millis();
  return true;
}

String buildTelemetry() {
  return String(Encoder1Acond) + "J" + String(Encoder2Acond) + "J" + String(Encoder3Acond) + "J"
       + String(Encoder4Acond) + "J" + String(targetServoPos) + "J" + String(Encoder5Acond) + "J" + String(0);
}

String buildStatusJson() {
  String j = "{";
  j += "\"enc1\":" + String(encoder1.getCount()) + ",";
  j += "\"enc2\":" + String(encoder2.getCount()) + ",";
  j += "\"enc3\":" + String(encoder3.getCount()) + ",";
  j += "\"enc4\":" + String(encoder4.getCount()) + ",";
  j += "\"enc5\":" + String(encoder5.getCount()) + ",";
  j += "\"tgt1\":" + String(targetPos1) + ",";
  j += "\"tgt2\":" + String(targetPos2) + ",";
  j += "\"tgt3\":" + String(targetPos3) + ",";
  j += "\"tgt4\":" + String(targetPos4) + ",";
  j += "\"tgt5\":" + String(targetPos5) + ",";
  j += "\"servo\":" + String(targetServoPos) + ",";
  j += "\"grados\":[" + String(Encoder1Acond) + "," + String(Encoder2Acond) + "," + String(Encoder3Acond)
                      + "," + String(Encoder4Acond) + "," + String(Encoder5Acond) + "],";
  j += "\"estados\":[" + String(stateMotor1) + "," + String(stateMotor2) + "," + String(stateMotor3)
                      + "," + String(stateMotor4) + "," + String(stateMotor5) + "],";
  j += "\"modo\":\"" + String(staConectado ? "STA+AP" : "AP") + "\",";
  j += "\"ip\":\"" + (staConectado ? WiFi.localIP().toString() : WiFi.softAPIP().toString()) + "\",";
  j += "\"uptime_s\":" + String(millis() / 1000);
  j += "}";
  return j;
}

String buildSensorsJson() {
  String j = "{";
  j += "\"PULGAR_F\":"  + String(datos.PULGAR_F)  + ",";
  j += "\"INDICE_F\":"  + String(datos.INDICE_F)  + ",";
  j += "\"MEDIO_F\":"   + String(datos.MEDIO_F)   + ",";
  j += "\"ANULAR_F\":"  + String(datos.ANULAR_F)  + ",";
  j += "\"MENIQUE_F\":" + String(datos.MENIQUE_F) + ",";
  j += "\"MENIQUE_M\":" + String(datos.MENIQUE_M) + ",";
  j += "\"MENIQUE_I\":" + String(datos.MENIQUE_I) + ",";
  j += "\"ANULAR_M\":"  + String(datos.ANULAR_M)  + ",";
  j += "\"ANULAR_I\":"  + String(datos.ANULAR_I)  + ",";
  j += "\"MEDIO_M\":"   + String(datos.MEDIO_M)   + ",";
  j += "\"MEDIO_I\":"   + String(datos.MEDIO_I)   + ",";
  j += "\"INDICE_M\":"  + String(datos.INDICE_M)  + ",";
  j += "\"INDICE_I\":"  + String(datos.INDICE_I)  + ",";
  j += "\"PULGAR_M\":"  + String(datos.PULGAR_M)  + ",";
  j += "\"PULGAR_I\":"  + String(datos.PULGAR_I)  + ",";
  j += "\"PULGAR_In\":" + String(datos.PULGAR_In);
  j += "}";
  return j;
}

// ========================== MUX / CONTROL ==========================

void selectChannel(int channel) { //Canales para mux
  digitalWrite(S0_PIN, channel & 0x01);
  digitalWrite(S1_PIN, (channel >> 1) & 0x01);
  digitalWrite(S2_PIN, (channel >> 2) & 0x01);
  digitalWrite(S3_PIN, (channel >> 3) & 0x01);
}

void mux(unsigned long currentMicros) { //funcion para realizar lectura del mux en nucleo 0
  if (currentMicros - previousMicrosMux >= waitTime) {
    for (int channel = 0; channel < 16; channel++) {

      selectChannel(channel);
      int value = analogRead(SIG_PIN);

      // Guardar el valor en la estructura - revisar entradas verdes de la pcb para asignacion canal
      switch (channel) {
        case 0:  datos.PULGAR_F  = value; break;
        case 1:  datos.INDICE_F  = value; break;
        case 2:  datos.MEDIO_F   = value; break;
        case 3:  datos.ANULAR_F  = value; break;
        case 4:  datos.MENIQUE_F = value; break;
        case 5:  datos.MENIQUE_M = value; break; //PUNTO1
        case 6:  datos.MENIQUE_I = value; break;
        case 7:  datos.ANULAR_M  = value; break;
        case 8:  datos.ANULAR_I  = value; break;
        case 9:  datos.MEDIO_M   = value; break;
        case 10: datos.MEDIO_I   = value; break;
        case 11: datos.INDICE_M  = value; break;
        case 12: datos.INDICE_I  = value; break;
        case 13: datos.PULGAR_M  = value; break;
        case 14: datos.PULGAR_I  = value; break;
        case 15: datos.PULGAR_In = value; break;
      }
    }
    // Actualizacion
    previousMicrosMux = currentMicros;
  }
}

void updateMotorPositions() {
  long currentPos1 = encoder1.getCount();
  long currentPos2 = encoder2.getCount();
  long currentPos3 = encoder3.getCount();
  long currentPos4 = encoder4.getCount();
  long currentPos5 = encoder5.getCount();

  // Controlador PI para Motor 1
  long error1 = targetPos1 - currentPos1;
  integral1 += error1;

  int speed1 = constrain(Kp1 * error1 + Ki * integral1, -255, 255);
  if (abs(error1) > 20) {
    if (error1 > 0) {
      motor1->setSpeed(abs(speed1));
      motor1->run(BACKWARD);
      stateMotor1 = 1;
    } else {
      motor1->setSpeed(abs(speed1));
      motor1->run(FORWARD);
      stateMotor1 = 1;
    }
  } else {
    motor1->run(RELEASE);
    stateMotor1 = 0;
    integral1 = 0; // Resetea el termino integral cuando el motor se detiene
  }

  // Controlador PI para Motor 2
  long error2 = targetPos2 - currentPos2;
  integral2 += error2;

  int speed2 = constrain(Kp * error2 + Ki * integral2, -255, 255);
  if (abs(error2) > 20) { // Margen de error necesario para que no oscile en un punto
    if (error2 > 0) {
      motor2->setSpeed(abs(speed2));
      motor2->run(FORWARD);
      stateMotor1 = 1;
    } else {
      motor2->setSpeed(abs(speed2));
      motor2->run(BACKWARD);
      stateMotor2 = 1;
    }
  } else {
    motor2->run(RELEASE);
    stateMotor2 = 0;
    integral2 = 0;
  } // Resetea el termino integral cuando el motor se detiene

  // Controlador PI para Motor 3
  long error3 = targetPos3 - currentPos3;
  integral3 += error3;

  int speed3 = constrain(Kp * error3 + Ki * integral3, -255, 255);
  if (abs(error3) > 20) { // Margen de error necesario para que no oscile en un punto
    if (error3 > 0) {
      motor3->setSpeed(abs(speed3));
      motor3->run(FORWARD);
      stateMotor1 = 1;
    } else {
      motor3->setSpeed(abs(speed3));
      motor3->run(BACKWARD);
      stateMotor3 = 1;
    }
  } else {
    motor3->run(RELEASE);
    stateMotor3 = 0;
    integral3 = 0; // Resetea el termino integral cuando el motor se detiene
  }

  // Controlador PI para Motor 4
  long error4 = targetPos4 - currentPos4;
  integral4 += error4;

  int speed4 = constrain(Kp4 * error4 + Ki * integral4, -255, 255);
  if (abs(error4) > 20) { // Margen de error necesario para que no oscile en un punto
    if (error4 > 0) {
      motor4->setSpeed(abs(speed4));
      motor4->run(FORWARD);
      stateMotor4 = 1;
    } else {
      motor4->setSpeed(abs(speed4));
      motor4->run(BACKWARD);
      stateMotor4 = 1;
    }
  } else {
    motor4->run(RELEASE);
    stateMotor4 = 0;
    integral4 = 0; // Resetea el termino integral cuando el motor se detiene
  }

  if (currentPos5 < targetPos5 - 30) {
    motor5->run(BACKWARD);
    stateMotor5 = 1;
  } else if (currentPos5 > targetPos5 + 30) {
    motor5->run(FORWARD);
    stateMotor5 = 1;
  } else {
    motor5->run(RELEASE);
    stateMotor5 = 0;
  }

  // Mover el servomotor a la posicion objetivo
  static int lastServoPos = -1;  // Guardar la ultima posicion del servomotor
  if (lastServoPos != targetServoPos) {
    myServo.write(targetServoPos);
    lastServoPos = targetServoPos;
  }
}

void parseAndSetTargetPositions(String input) {
  input.trim();  // Eliminar espacios en blanco alrededor de la entrada

  // Comprobar si el comando es 'S' para detener los motores
  if (input == "S") { //Detener los motores
    stopMotors();
    return;
  }

  if (input == "G") { //Pointing something
    moveToPositions(450, 500, 600, 0, 150, 200);
    return;
  }

  if (input == "O") { //Open Hand
    moveToPositions(0, 0, 0, 0, 0, 0);
    return;
  }

  if (input == "I") { //Inicializar ambas shields en caso de desconexion
    if (AFMS1.begin()) {
      Serial.println("Shield 1 inicializada correctamente.");
    } else {
      Serial.println("Error al inicializar la Shield 1.");
    }
    if (AFMS2.begin()) {
      Serial.println("Shield 2 inicializada correctamente.");
    } else {
      Serial.println("Error al inicializar la Shield 2.");
    }
    return;
  }

  if (input == "R") { //Spiderman
    moveToPositions(0, 500, 650, 0, 0, 0);
    return;
  }

  if (input == "P") { //Rutina "OK"
    moveToPositions(0, 0, 500, 0, 150, 225);
    return;
  }
  if (input == "W") { //Claw
    moveToPositions(0, 500, 0, 400, 0, 0);
    return;
  }
  if (input == "Y") { //Okay Sign
    moveToPositions(0, 0, 0, 350, 150, 200);
    return;
  }
  if (input == "L") { //Like
    moveToPositions(600, 450, 600, 400, 0, 0);
    return;
  }
  if (input == "M") { //Call-me
    moveToPositions(0, 450, 600, 400, 0, 0);
    return;
  }
  if (input == "H") { //Three
    moveToPositions(600, 0, 0, 0, 150, 200);
    return;
  }
  if (input == "U") { //Four
    moveToPositions(0, 0, 0, 0, 150, 200);
    return;
  }

  if (input == "C") { //Close Hand
    moveToPositions(600, 450, 600, 400, 125, 100);
    return;
  }

  if (input == "X") { //Calibracion de encoders, posicion actual = 0 en todos los motores
    encoder1.setCount(0);
    encoder2.setCount(0);
    encoder3.setCount(0);
    encoder4.setCount(0);
    encoder5.setCount(0);
    targetPos1 = 0;
    targetPos2 = 0;
    targetPos3 = 0;
    targetPos4 = 0;
    targetPos5 = 0;
    return;
  }

  // Procesar la entrada en el formato A<pos1>,B<pos2>,C<pos3>,D<pos4>,E<servoPos>,F<pos5>
  // Orden no importa
  int indexA = input.indexOf('A');
  int indexB = input.indexOf('B');
  int indexC = input.indexOf('C');
  int indexD = input.indexOf('D');  // Indice para el cuarto motor
  int indexE = input.indexOf('E');  // Indice para el servomotor
  int indexF = input.indexOf('F');  // Motor DC para mover pulgar

  if (indexA != -1) {
    int endIndex = input.indexOf(',', indexA);
    if (endIndex == -1) endIndex = input.length();
    targetPos1 = input.substring(indexA + 1, endIndex).toInt();
    Serial.print("Nueva posicion objetivo para Motor 1: ");
    Serial.println(targetPos1);
  }

  if (indexB != -1) {
    int endIndex = input.indexOf(',', indexB);
    if (endIndex == -1) endIndex = input.length();
    targetPos2 = input.substring(indexB + 1, endIndex).toInt();
    Serial.print("Nueva posicion objetivo para Motor 2: ");
    Serial.println(targetPos2);
  }

  if (indexC != -1) {
    int endIndex = input.indexOf(',', indexC);
    if (endIndex == -1) endIndex = input.length();
    targetPos3 = input.substring(indexC + 1, endIndex).toInt();
    Serial.print("Nueva posicion objetivo para Motor 3: ");
    Serial.println(targetPos3);
  }

  if (indexD != -1) {
    int endIndex = input.indexOf(',', indexD);
    if (endIndex == -1) endIndex = input.length();
    targetPos4 = input.substring(indexD + 1, endIndex).toInt();
    Serial.print("Nueva posicion objetivo para Motor 4: ");
    Serial.println(targetPos4);
  }

  if (indexE != -1) {
    int endIndex = input.indexOf(',', indexE);
    if (endIndex == -1) endIndex = input.length();
    targetServoPos = input.substring(indexE + 1, endIndex).toInt();
    /*
    // ---------------- SERVO LIMIT CLAMP (MECHANICAL LIMITS) ----------------
    if (targetServoPos > 125) {
      targetServoPos = 125;          // Upper mechanical limit
    } else if (targetServoPos <= 10) {
      targetServoPos = 10;           // Lower mechanical limit (avoid 0-1)
    }
    // ----------------------------------------------------------------------
    */
    Serial.print("Nueva posicion objetivo para el Servomotor: ");
    Serial.println(targetServoPos);
  }

  if (indexF != -1) {
    int endIndex = input.indexOf(',', indexF);
    if (endIndex == -1) endIndex = input.length();
    targetPos5 = input.substring(indexF + 1, endIndex).toInt();
    Serial.print("Nueva posicion objetivo para Motor 5: ");
    Serial.println(targetPos5);
  }

  if (indexA == -1 && indexB == -1 && indexC == -1 && indexD == -1 && indexE == -1 && indexF == -1) {
    Serial.println("Formato de entrada incorrecto. Use: A<pos1>,B<pos2>,C<pos3>,D<pos4>,E<servoPos>,F<pos5>");
  }
}

void stopMotors() {
  //Detener todos los motores
  motor1->run(RELEASE);
  motor2->run(RELEASE);
  motor3->run(RELEASE);
  motor4->run(RELEASE);
  motor5->run(RELEASE);
  targetPos1 = encoder1.getCount();  // Establecer la posicion actual como objetivo
  targetPos2 = encoder2.getCount();
  targetPos3 = encoder3.getCount();
  targetPos4 = encoder4.getCount();
  targetPos5 = encoder5.getCount();
  targetServoPos = myServo.read();   // Posicion actual del servomotor como objetivo
  Serial.println("Motors stopped.");
}

void moveToPositions(long position1, long position2, long position3, long position4, int servoPos, long position5) {
  targetPos1 = position1;
  targetPos2 = position2;
  targetPos3 = position3;
  targetPos4 = position4;
  targetPos5 = position5;
  targetServoPos = servoPos;  // Establecer la posicion objetivo del servomotor
}

// ===================== FUNCIONES DE SEGURIDAD =====================

void rearmAfterIdle() {
  // Stop all motors
  motor1->run(RELEASE);
  motor2->run(RELEASE);
  motor3->run(RELEASE);
  motor4->run(RELEASE);
  motor5->run(RELEASE);

  // Reset integrators to avoid post-idle kick
  integral1 = integral2 = integral3 = integral4 = 0;

  // Snap targets to current positions so the controller has no latent jump
  targetPos1 = encoder1.getCount();
  targetPos2 = encoder2.getCount();
  targetPos3 = encoder3.getCount();
  targetPos4 = encoder4.getCount();
  targetPos5 = encoder5.getCount();
  targetServoPos = myServo.read();
}

bool isLikelyValidCommand(const String& sIn) {
  String s = sIn;
  s.trim();
  if (s.length() == 0) return false;

  // Accept single-letter commands (gestures)
  if (s.length() == 1) {
    char c = s.charAt(0);
    return (c=='S'||c=='G'||c=='O'||c=='I'||c=='R'||c=='P'||c=='W'||c=='Y'||c=='L'||c=='M'||c=='H'||c=='U'||c=='C'||c=='X');
  }

  // For multi-field commands, accept only characters you actually use:
  // A-F identifiers, digits, sign, comma, spaces.
  for (int i = 0; i < (int)s.length(); i++) {
    char c = s[i];
    bool ok =
      (c >= 'A' && c <= 'F') ||
      (c >= '0' && c <= '9') ||
      (c == '-') || (c == ',') || (c == ' ');
    if (!ok) return false;
  }

  // Must contain at least one field letter
  return (s.indexOf('A')!=-1 || s.indexOf('B')!=-1 || s.indexOf('C')!=-1 ||
          s.indexOf('D')!=-1 || s.indexOf('E')!=-1 || s.indexOf('F')!=-1);
}
