#include <Wire.h>
#include <Adafruit_MotorShield.h>
#include <ESP32Encoder.h> 
#include <ESP32Servo.h>
#include <BluetoothSerial.h> 

TaskHandle_t Nucleo1;
TaskHandle_t Nucleo2;

// Crear instancias de las shield
Adafruit_MotorShield AFMS1 = Adafruit_MotorShield(0x60);  // Dirección I2C por defecto - shield bot
Adafruit_MotorShield AFMS2 = Adafruit_MotorShield(0x61);  // Dirección I2C estañada - shield top

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
#define SIG_PIN 35


Servo myServo;  // Crear un objeto Servo
const int servoPin = 13;  // Pin donde está conectado el servomotor

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

// Variables de posición
long targetPos1 = 0;
long targetPos2 = 0;
long targetPos3 = 0;  // Nueva variable
long targetPos4 = 0;  // Nueva variable
long targetPos5 = 0;  // Nueva variable
int targetServoPos = 0;  // Posición objetivo del servomotor
//para bucle de impresion
unsigned long lastUpdateTime = 0;
unsigned long lastPrintTime = 0;
unsigned long lastUpdateTimeMux=0;
const unsigned long updateInterval = 100;  // Intervalo de actualización en milisegundos
const unsigned long printInterval = 500;   // Intervalo de impresión en milisegundos

// Parámetros del controlador PI
const float Kp = 0.25;  // Ganancia proporcional se debe ajustar según el máximo error 400
const float Ki = 0.05;
const float Kp1 = 0.5;
const float Kp4 = 0.5;
const float Kp3 = 0.25;
// Acumuladores de error para el término integral - Suma de Riemann
float integral1 = 0;
float integral2 = 0;
float integral3 = 0;
float integral4 = 0;

long Encoder1Acond=0;
long Encoder2Acond=0;
long Encoder3Acond=0;
long Encoder4Acond=0;
long Encoder5Acond=0;

//Bluetooth
BluetoothSerial SerialBT;  // Crear una instancia de BluetoothSerial

// Variables para verificar el movimiento del encoder
long lastPos1 = 0;
long lastPos2 = 0;
long lastPos3 = 0;
long lastPos4 = 0;
long lastPos5 = 0;

unsigned long lastMuxUpdateTime = 0; //auxiliar
unsigned long CheckInterval = 10; // Intervalo para verificar el movimiento en milisegundos
int currentMuxChannel=0;
// Variables para lectura de datos
unsigned long waitTime = 500; // Tiempo en milisegundos
unsigned long previousMicrosMux = 0;


// ---------------- Bluetooth RX + Idle re-arm ----------------
static String btLine;
static bool btLineReady = false;
static unsigned long lastBtByteMs = 0;

const size_t BT_MAX_LINE = 80;                 // safety: drop absurdly long frames
const unsigned long BT_LINE_TIMEOUT_MS = 200;  // drop partial line if it stalls

static unsigned long lastValidCmdMs = 0;
static bool idleArmed = false;
const unsigned long IDLE_ARM_MS = 30000;       // after 15s without a valid command, re-arm on next

static bool lastHasClient = false;
// ------------------------------------------------------------


enum InputSource { SERIAL_IN, BLUETOOTH_IN };
InputSource currentSource = SERIAL_IN;

//Declaración de funciones
void selectChannel(int channel);
void mux(unsigned long currentMicros);


void updateMotorPositions();
void parseAndSetTargetPositions(String input);
void stopMotors();
//void readMuxValues();
void moveToPositions(long position1, long position2, long position3, long position4, int servoPos, long position5);  // Nueva firma de función
//estructura de dato para lectura mux 
//Multiplexer mux;

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

//void TareaNucleo1(void * pvParameters){
//for (;;){

// }}

void TareaNucleo2(void * pvParameters){
for (;;){
  unsigned long currentMillis = millis();
 //if (currentMillis - lastMuxUpdateTime >= muxInterval) {
      lastMuxUpdateTime = currentMillis;
      mux(currentMillis);
  //  }
     
vTaskDelay(10);  // Agregar un pequeño retardo para liberar el CPU
}}


void setup() {
  Serial.begin(115200);
  SerialBT.begin("HANDI_EPN"); //Nombre de la esp BT
  lastValidCmdMs = millis();

 
 //xTaskCreatePinnedToCore(TareaNucleo1,"Tarea1",10000,NULL,1,&Nucleo1,1);
  xTaskCreatePinnedToCore(TareaNucleo2,"Tarea2",10000,NULL,1,&Nucleo2,0);

  // Inicializar las shield y los motores
  AFMS1.begin(); 
  AFMS2.begin(); 
  pinMode(S0_PIN, OUTPUT);
  pinMode(S1_PIN, OUTPUT);
  pinMode(S2_PIN, OUTPUT);
  pinMode(S3_PIN, OUTPUT);

 if(currentSource==SERIAL_IN){
  Serial.println("Motor shields initialized.");}
  //Inicializar mux
 // mux.begin(33, 15, 2, 4, 35); // Pines S0, S1, S2, S3, EN y SIG


//Arriba M1 DEDO 5 M2 DEDO 2 M3 DEDO 3
//dedo 5 sería el movimiendo del pulgar
//ABAJO M1 DEEDO 1 M2 DEDO 4

  // Asignar los motores a las shield
  motor1 = AFMS1.getMotor(1);  // Motor 1 en la primera shield
  motor2 = AFMS2.getMotor(2);  // Motor 2 en la primera shield
  motor3 = AFMS2.getMotor(3);  // Motor 3 en la segunda shield
  motor4 = AFMS1.getMotor(2);  // Motor 4 en la segunda shield
  motor5 = AFMS2.getMotor(1);  // Motor 5 en segunda shield
   if(currentSource==SERIAL_IN){
  Serial.println("Motors assigned.");}

  // Configurar velocidad inicial de los motores - motores sin control P de posición = F
  motor1->setSpeed(50);  // Máxima velocidad
  motor2->setSpeed(50);  // Máxima velocidad
  motor3->setSpeed(50);  // Máxima velocidad
  motor4->setSpeed(50);  // Máxima velocidad
  motor5->setSpeed(50);  // Máxima velocidad

  // Inicializar los encoders
  //ESP32Encoder::useInternalWeakPullResistors = puType::down;
  ESP32Encoder::useInternalWeakPullResistors = puType::up;
  if(currentSource==SERIAL_IN){
  Serial.println("Initializing encoders...");}

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

  if(currentSource==SERIAL_IN){
  Serial.println("Encoders initialized.");}

  // Inicializar el servomotor
  myServo.attach(servoPin);

}

void loop() {
  // Comprobar si hay datos disponibles en Serial
  if (Serial.available() > 0) {
    currentSource = SERIAL_IN;
    String input = Serial.readStringUntil('\n');
    Serial.print("Serial input received: ");
    Serial.println(input);
    parseAndSetTargetPositions(input);
  }

/*
// Comprobar si hay datos disponibles en bt
  if (SerialBT.available() > 0) {
    currentSource = BLUETOOTH_IN;
    String input = SerialBT.readStringUntil('\n');
    parseAndSetTargetPositions(input); }
*/

// Detect BT client connect/disconnect; on transitions, flush/rearm to avoid stale bursts
bool hasClient = SerialBT.hasClient();
if (hasClient != lastHasClient) {
  lastHasClient = hasClient;
  rearmAfterIdle();
  idleArmed = false;
}

// If we have been idle too long, arm the rearm routine
unsigned long now = millis();
if (!idleArmed && (now - lastValidCmdMs) > IDLE_ARM_MS) {
  idleArmed = true;
}

// Non-blocking BT line receive
if (SerialBT.available() > 0) {
  currentSource = BLUETOOTH_IN;
  readBluetoothLineNonBlocking();

  if (btLineReady) {
    String input = btLine;
    btLine = "";
    btLineReady = false;

    // If we were idle-armed, rearm BEFORE applying the first post-idle frame
    if (idleArmed) {
      rearmAfterIdle();
      idleArmed = false;
    }

    // Apply only if frame looks valid; otherwise discard and flush
    if (isLikelyValidCommand(input)) {
      parseAndSetTargetPositions(input);
      lastValidCmdMs = millis();
    } else {
      // Drop garbage and clear any remaining bytes from a corrupted burst
      while (SerialBT.available() > 0) (void)SerialBT.read();
    }
  }
}


  // Actualizar la posición de los motores periódicamente sin bloquear el ciclo principal - No usar delay
  unsigned long currentMillis = millis();

  
  if (currentMillis - lastUpdateTime >= updateInterval) {
    lastUpdateTime = currentMillis;
    updateMotorPositions(); //aactualizo la posicion de los motores
  }

  // Imprimir la posición actual de los encoders cada cierto intervalo
  if (currentMillis - lastPrintTime >= printInterval) {
    lastPrintTime = currentMillis;
    Encoder1Acond=map(encoder1.getCount(),0,400,0,90);
    Encoder2Acond=map(encoder2.getCount(),0,400,0,90);
    Encoder3Acond=map(encoder3.getCount(),0,500,0,90);
    Encoder4Acond=map(encoder4.getCount(),0,400,0,90);
    Encoder5Acond=map(encoder5.getCount(),0,200,0,70);  

    if(currentSource==SERIAL_IN){

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
      Serial.print("\t Nucloe: ");
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
  else{
    //Trama para enviar a la aplicación en appInventor
    SerialBT.println(String(Encoder1Acond)+"J"+String(Encoder2Acond)+"J"+String(Encoder3Acond)+"J"
    +String(Encoder4Acond)+"J"+String(targetServoPos)+"J"+String(Encoder5Acond)+"J"+String(0));

    /*
    //DEBUGGING CODE
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
    */
  }
  }
}

void selectChannel(int channel) { //Canales para mux
  digitalWrite(S0_PIN, channel & 0x01);
  digitalWrite(S1_PIN, (channel >> 1) & 0x01);
  digitalWrite(S2_PIN, (channel >> 2) & 0x01);
  digitalWrite(S3_PIN, (channel >> 3) & 0x01);
}


void mux(unsigned long currentMicros){ //funcion para realizar lectura del mux en nucleo 0
  if (currentMicros - previousMicrosMux >= waitTime) {
  for (int channel = 0; channel < 16; channel++) {
  
    selectChannel(channel);
    int value = analogRead(SIG_PIN);

    // Guardar el valor en la estructura - revisar entradas verdes de la pcb para asignacion canal
    switch (channel) {
      case 0: datos.PULGAR_F = value; break;
      case 1: datos.INDICE_F = value; break;
      case 2: datos.MEDIO_F = value; break;
      case 3: datos.ANULAR_F = value; break;
      case 4: datos.MENIQUE_F = value; break;
      case 5: datos.MENIQUE_M = value; break; //PUNTO1
      case 6: datos.MENIQUE_I = value; break;
      case 7: datos.ANULAR_M = value; break;
      case 8: datos.ANULAR_I = value; break;
      case 9: datos.MEDIO_M = value; break;
      case 10: datos.MEDIO_I = value; break;
      case 11: datos.INDICE_M = value; break;
      case 12: datos.INDICE_I = value; break;
      case 13: datos.PULGAR_M = value; break;
      case 14: datos.PULGAR_I = value; break;
      case 15: datos.PULGAR_In = value; break;
    }   
  }
  // Actualizacion
  previousMicrosMux = currentMicros;
  }}



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
  integral1 = 0; // Resetea el término integral cuando el motor se detiene
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
  integral2 = 0;} // Resetea el término integral cuando el motor se detiene

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
  integral3 = 0; // Resetea el término integral cuando el motor se detiene
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
  integral4 = 0; // Resetea el término integral cuando el motor se detiene
}

  if (currentPos5 < targetPos5 - 30) {
    motor5->run(BACKWARD);
     stateMotor5 = 1;
  } else if (currentPos5 > targetPos5 + 30) {
    motor5->run(FORWARD);
     stateMotor5 = 1;
  } else {
    motor5->run(RELEASE);
    stateMotor5 = 0;}

  // Mover el servomotor a la posición objetivo
static int lastServoPos = -1;  // Guardar la última posición del servomotor
  if (lastServoPos != targetServoPos) {
    myServo.write(targetServoPos);
    lastServoPos = targetServoPos;}
}

void parseAndSetTargetPositions(String input) {
  input.trim();  // Eliminar espacios en blanco alrededor de la entrada

  // Comprobar si el comando es 'S' para detener los motores
  if (input == "S") { //Detener los motores
    stopMotors();
    return;}  // Salir de la función inmediatamente

  if (input == "G") { //Pointing something
    moveToPositions(450, 500, 600, 0, 150, 200);
    return;  // Salir de la función inmediatamente
  }

  if (input == "O") { //Open Hand
    moveToPositions(0, 0, 0, 0, 0, 0);
    return;  // Salir de la función inmediatamente
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
    return;  // Salir de la función inmediatamente
  }

  if (input == "R") { //Spiderman
    moveToPositions(0, 500, 650, 0, 0, 0);
    return;}  // Salir de la función inmediatamente

  if (input == "P") { //Rutina "OK" 
    moveToPositions(0, 0, 500, 0, 150, 225);
    return;}  // Salir de la función inmediatamente
  if (input == "W") { //Claw 
    moveToPositions(0, 500, 0, 400, 0, 0);
    return;}  // Salir de la función inmediatamente
  if (input == "Y") { //Okay Sign 
    moveToPositions(0, 0, 0, 350, 150, 200);
    return;}
  if (input == "L") { //Like 
    moveToPositions(600, 450, 600, 400, 0, 0);
    return;}
  if (input == "M") { //Call-me
    moveToPositions(0, 450, 600, 400, 0, 0);
    return;}
  if (input == "H") { //Three
    moveToPositions(600, 0, 0, 0, 150, 200);
    return;}
  if (input == "U") { //Four
    moveToPositions(0, 0, 0, 0, 150, 200);
    return;}

  if (input == "C") { //Close Hand
    moveToPositions(600, 450, 600, 400, 125, 100);
    return;}  // Salir de la función inmediatamente

 if (input == "X") { //Calibracion de encoders, inicializar de nuevo la posicion inicial - actual a 0 en todos los motores
    encoder1.setCount(0);
    encoder2.setCount(0);
    encoder3.setCount(0);
    encoder4.setCount(0);
    encoder5.setCount(0);
    targetPos1=0;
    targetPos2=0;
    targetPos3=0;
    targetPos4=0;
    targetPos5=0;
    return;}  // Salir de la función inmediatamente
    
  // Procesar la entrada en el formato A<posicion1>, B<posicion2>, y/o C<posicion3>, D<posicion4>, E<servoPos>

  // Orden no importa
  int indexA = input.indexOf('A');
  int indexB = input.indexOf('B');
  int indexC = input.indexOf('C');
  int indexD = input.indexOf('D');  // Nuevo índice para el cuarto motor
  int indexE = input.indexOf('E');  // Índice para el servomotor
  int indexF = input.indexOf('F');  // Motor DC para mover pulgar

  if (indexA != -1) {
    int endIndex = input.indexOf(',', indexA);
    if (endIndex == -1) endIndex = input.length();
    targetPos1 = input.substring(indexA + 1, endIndex).toInt();
     if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para Motor 1: ");
    Serial.println(targetPos1);}
  }

  if (indexB != -1) {
    int endIndex = input.indexOf(',', indexB);
    if (endIndex == -1) endIndex = input.length();
    targetPos2 = input.substring(indexB + 1, endIndex).toInt();
     if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para Motor 2: ");
    Serial.println(targetPos2);}
  }

  if (indexC != -1) {
    int endIndex = input.indexOf(',', indexC);
    if (endIndex == -1) endIndex = input.length();
    targetPos3 = input.substring(indexC + 1, endIndex).toInt();
     if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para Motor 3: ");
    Serial.println(targetPos3);}
  }

  if (indexD != -1) {
    int endIndex = input.indexOf(',', indexD);
    if (endIndex == -1) endIndex = input.length();
    targetPos4 = input.substring(indexD + 1, endIndex).toInt();
     if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para Motor 4: ");
    Serial.println(targetPos4);}
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
      targetServoPos = 10;            // Lower mechanical limit (avoid 0–1)
    }
    // ----------------------------------------------------------------------
    */
    if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para el Servomotor: ");
    Serial.println(targetServoPos);}
  }

  if (indexF != -1) {
    int endIndex = input.indexOf(',', indexF);
    if (endIndex == -1) endIndex = input.length();
    targetPos5 = input.substring(indexF + 1, endIndex).toInt();
     if(currentSource==SERIAL_IN){
    Serial.print("Nueva posición objetivo para Motor 5: ");
    Serial.println(targetPos5);}
  }

  if (indexA == -1 && indexB == -1 && indexC == -1 && indexD == -1 && indexE == -1&& indexF == -1) {
     if(currentSource==SERIAL_IN){
    Serial.println("Formato de entrada incorrecto. Use: A<posicion1>,B<posicion2>,C<posicion3>,D<posicion4>,E<servoPos> o combinaciones de A, B, C, D y E");
  }}
}

void stopMotors() {
  //Detener todos los motores
  motor1->run(RELEASE);
  motor2->run(RELEASE);
  motor3->run(RELEASE);
  motor4->run(RELEASE);  
  motor5->run(RELEASE);  
  targetPos1 = encoder1.getCount();  // Establecer la posición actual como objetivo
  targetPos2 = encoder2.getCount();  // Establecer la posición actual como objetivo
  targetPos3 = encoder3.getCount();  // Establecer la posición actual como objetivo
  targetPos4 = encoder4.getCount();  // Establecer la posición actual como objetivo
  targetPos5 = encoder5.getCount();  // Establecer la posición actual como objetivo
  targetServoPos = myServo.read();  // Establecer la posición actual del servomotor como objetivo
  if(currentSource==SERIAL_IN){
  Serial.println("Motors stopped.");
   }
}

void moveToPositions(long position1, long position2, long position3, long position4, int servoPos, long position5) {
  targetPos1 = position1;
  targetPos2 = position2;
  targetPos3 = position3;
  targetPos4 = position4;
  targetPos5 = position5;
  targetServoPos = servoPos;  // Establecer la posición objetivo del servomotor
}


//NEW FUNCTIONS

void readBluetoothLineNonBlocking() {
  // If a line started but then stalled, drop it (prevents applying partial frames)
  if (btLine.length() > 0 && (millis() - lastBtByteMs) > BT_LINE_TIMEOUT_MS) {
    btLine = "";
  }

  while (SerialBT.available() > 0) {
    char c = (char)SerialBT.read();
    lastBtByteMs = millis();

    if (c == '\r') continue;          // ignore CR
    if (c == '\n') {                  // newline terminates a frame
      btLineReady = true;
      return;
    }

    // keep only printable ASCII to avoid control-character garbage
    if (c >= 32 && c <= 126) {
      if (btLine.length() < BT_MAX_LINE) {
        btLine += c;
      } else {
        // too long -> drop frame
        btLine = "";
      }
    }
  }
}


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

  // Flush stale bytes in Bluetooth RX and clear partial frame
  while (SerialBT.available() > 0) (void)SerialBT.read();
  btLine = "";
  btLineReady = false;
}

bool isLikelyValidCommand(const String& sIn) {
  String s = sIn;
  s.trim();
  if (s.length() == 0) return false;

  // Accept single-letter commands (gestures)
  if (s.length() == 1) {
    char c = s.charAt(0);
    // Permit your known single-letter commands. Extend if needed.
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
