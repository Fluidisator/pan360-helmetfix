#include <M5StickCPlus2.h>
#include <BLEDevice.h>
#include "SPIFFS.h"
#include <WiFi.h>
#include <WebServer.h>

// Configuration vars
/* WiFi */
//reseau actif
int numwifi = 0;
// nombre de réseau
int nbwifi = 2;
//Delay between short and long press
bool btnbactivate = true;
// Wifi SSID
const char* ssid[2] = {"SSID1","SSID2"};
// Wifi Password
const char* password[2] = {"Password1","Password2"};
char NumDate [21];
bool boolsyncNTP = false;

// Witmotion sensor 
// Witmotion WT9011DCL-BT5 Mac Address
static const char* macStr = "01:23:45:67:89:ab";
// Witmotion WT9011DCL-BT5 serviceUUID 
static BLEUUID serviceUUID("0000ffe5-0000-1000-8000-00805f9a34fb");
// WitMotion WT9011DCL-BT5 characteristic UUID
static BLEUUID charUUID("0000ffe4-0000-1000-8000-00805f9a34fb");
BLEAddress deviceAddress(macStr);

String ip = "";

static boolean doConnect = false;
static boolean connected = false;
static boolean doScan = false;

static BLERemoteCharacteristic *pRemoteCharacteristic;
static BLEAdvertisedDevice *myDevice;

// Context vars
int screen = 1;
boolean wifienable = false;
int wifienabled = 0;

boolean screencolored = false;
boolean recordstarted = false;
int id = 0;
float roll = 0;
float pitch = 0;
float yaw = 0;
float accelx = 0;
float accely = 0;
float accelz = 0;
char filename[21];

WebServer server(80);

File logFile;
unsigned long timems;
unsigned long lastRecord = millis();
unsigned long lastWifiAttempt = millis();
unsigned long lastBLEAttempt = millis();

//NTP config
//From M5StickC plus 2 RTC example
#define NTP_TIMEZONE  "UTC+2"
#define NTP_SERVER1   "ntp.midway.ovh"
#define NTP_SERVER2   "ntp.unice.fr"
#define NTP_SERVER3   "delphi.phys.univ-tours.fr"

// Different versions of the framework have different SNTP header file names and
// availability.
#if __has_include(<esp_sntp.h>)
#include <esp_sntp.h>
#define SNTP_ENABLED 1
#elif __has_include(<sntp.h>)
#include <sntp.h>
#define SNTP_ENABLED 1
#endif

#ifndef SNTP_ENABLED
#define SNTP_ENABLED 0
#endif

void handleRoot() {
  String html = "<h1>Fichiers SPIFFS</h1><ul>";

  File root = SPIFFS.open("/");
  File file = root.openNextFile();
  while (file) {
    String name = file.name();
    html += "<li><a href='/download?file=" + name + "'>" + name + "</a></li>";
    file = root.openNextFile();
  }

  html += "</ul>";
  server.send(200, "text/html", html);
}

void handleDownload() {
  if (!server.hasArg("file")) {
    server.send(400, "text/plain", "Fichier manquant");
    return;
  }

  String filename = server.arg("file");
  String path = "/" + server.arg("file");
  if (!SPIFFS.exists(path)) {
    server.send(404, "text/plain", "Fichier non trouvé");
    return;
  }

  File file = SPIFFS.open(path, "r");
  server.sendHeader("Content-Disposition", "attachment; filename=\"" + filename + "\"");
  server.streamFile(file, "application/octet-stream");
  file.close();
}

static void notifyCallback(BLERemoteCharacteristic *pBLERemoteCharacteristic, uint8_t *pData, size_t length, bool isNotify) {   
  if(pData[1] == 97) {
    int rollL = pData[16];
    int rollH = pData[17];
    int pitchL = pData[14];
    int pitchH = pData[15];
    int yawL = pData[18];
    int yawH = pData[19];

    int16_t rollRaw  = (int16_t)((rollH << 8) | rollL) ;
    int16_t pitchRaw = (int16_t)((pitchH << 8) | pitchL);
    int16_t yawRaw   = (int16_t)((yawH << 8) | yawL) ;

    roll  = rollRaw / 32768.0 * 180.0;
    pitch = pitchRaw / 32768.0 * 180.0;
    yaw   = yawRaw / 32768.0 * 180.0;
  }
}

class MyClientCallback : public BLEClientCallbacks {
  void onConnect(BLEClient *pclient) {
    Serial.println("BLE connecté !");
  }

  void onDisconnect(BLEClient *pclient) {
    connected = false;
    Serial.println("onDisconnect");
    roll = 0;
    pitch = 0;
    yaw = 0;
  }
};

class MyAdvertisedDeviceCallbacks: public BLEAdvertisedDeviceCallbacks {
  void onResult(BLEAdvertisedDevice advertisedDevice) {
    Serial.print("BLE Advertised Device found: ");
    Serial.println(advertisedDevice.toString().c_str());
    
    if (advertisedDevice.getAddress().equals(deviceAddress)) {
      BLEDevice::getScan()->stop();
      myDevice = new BLEAdvertisedDevice(advertisedDevice);
      doConnect = true;
      doScan = false;
    }
  }
};

bool connectToServer() {
    Serial.print("Forming a connection to ");
    Serial.println(myDevice->getAddress().toString().c_str());
    
    BLEClient *pClient = BLEDevice::createClient();
    Serial.println(" - Created client");
 
    pClient->setClientCallbacks(new MyClientCallback());

    // Connect to the remove BLE Server.
    pClient->connect(myDevice);  // if you pass BLEAdvertisedDevice instead of address, it will be recognized type of peer device address (public or private)
    Serial.println(" - Connected to server");
    pClient->setMTU(517);  //set client to request maximum MTU from server (default is 23 otherwise)

    // Obtain a reference to the service we are after in the remote BLE server.
    BLERemoteService *pRemoteService = pClient->getService(serviceUUID);
    if (pRemoteService == nullptr) {
      Serial.print("Failed to find our service UUID: ");
      Serial.println(serviceUUID.toString().c_str());
      pClient->disconnect();
      return false;
    }
    Serial.println(" - Found our service");

    // Obtain a reference to the characteristic in the service of the remote BLE server.
    pRemoteCharacteristic = pRemoteService->getCharacteristic(charUUID);
    if (pRemoteCharacteristic == nullptr) {
      Serial.print("Failed to find our characteristic UUID: ");
      Serial.println(charUUID.toString().c_str());
      pClient->disconnect();
      return false;
    }
    Serial.println(" - Found our characteristic");
   
    if (pRemoteCharacteristic->canNotify()) {
      // Register/Subscribe for notifications
      pRemoteCharacteristic->registerForNotify(notifyCallback);
    }

    connected = true;
    return true;
  
}

void lcdon() {
      M5.Lcd.setBrightness(100);   // Rétroéclairage
      M5.Lcd.wakeup(); 
      StickCP2.Display.clear();
}
void lcdoff() {
      StickCP2.Display.clear();
      M5.Lcd.sleep(); 
}

String randomNumericBlock(int length) {
  String block = "";
  for (int i = 0; i < length; i++) {
    block += String(random(0, 10));  // chiffre entre 0 et 9
  }
  return block;
}

String generateRandomCode() {
  return randomNumericBlock(2) + "-" +
         randomNumericBlock(2) + "-" +
         randomNumericBlock(2) + "-" +
         randomNumericBlock(2);
}

//Synchronize RTC 
//From M5StickC plus 2 RTC example
void SyncNTP(){  
  configTzTime(NTP_TIMEZONE, NTP_SERVER1, NTP_SERVER2, NTP_SERVER3);

#if SNTP_ENABLED
    while (sntp_get_sync_status() != SNTP_SYNC_STATUS_COMPLETED) {
        Serial.print('.');
        delay(1000);
    }
#else
    delay(1600);
    struct tm timeInfo;
    while (!getLocalTime(&timeInfo, 1000)) {
        Serial.print('.');
    };
#endif

    Serial.println("\r\n NTP Connected.");

    time_t t = time(nullptr) + 1;  // Advance one second.
    while (t > time(nullptr));  /// Synchronization in seconds
    StickCP2.Rtc.setDateTime(gmtime(&t));
}

void setup() {
  M5.begin();
  M5.Lcd.setRotation(3);  // Orientation paysage
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setTextSize(2);
  M5.Lcd.setTextColor(WHITE, BLACK);
  M5.Lcd.setCursor(10, 10);
  M5.Lcd.println("Booting...");

  M5.Lcd.println("Init M5...");
  auto cfg = M5.config();
  StickCP2.begin(cfg);
    
  Serial.begin(115200);

  M5.Lcd.println("Init SPIFFS...");
  if (!SPIFFS.begin(true)) {
    Serial.println("Erreur SPIFFS");
    M5.Lcd.println("SPIFFS error...");
    return;
  }
  Serial.println("SPIFFS prêt");
  M5.Lcd.println("SPIFFS OK");

  Serial.println("Starting Arduino BLE Client application...");
  M5.Lcd.println("Starting BLE...");
  BLEDevice::init("");
  BLEScan* pBLEScan = BLEDevice::getScan();
  pBLEScan->setAdvertisedDeviceCallbacks(new MyAdvertisedDeviceCallbacks());
  pBLEScan->setInterval(1349);
  pBLEScan->setWindow(449);
  pBLEScan->setActiveScan(true);
  pBLEScan->start(5, false); // Scan 5 secondes sans blocage

  M5.Lcd.fillScreen(BLACK);
  
  if (!StickCP2.Rtc.isEnabled()) {
    Serial.println("RTC not found.");
    for (;;) {
      vTaskDelay(500);
    }
  }
  Serial.println("RTC found.");
  
}  // End of setup.

void loop() {
  timems = millis() / 100;
  
  auto dt = StickCP2.Rtc.getDateTime();
/*
// internal IMU
  auto imu_update = StickCP2.Imu.update();
  auto data = StickCP2.Imu.getImuData();
  accelx = data.accel.x;
  accely = data.accel.y;
  accelz = data.accel.z;

  roll = data.gyro.x;
  yaw = data.gyro.y;
  pitch = data.gyro.z;
*/

  StickCP2.update();
  if (StickCP2.BtnA.wasReleased()) {
    if(screen < 6) {
      lcdon();
      screen++ ;
      screencolored = false;
    }
    else {
      lcdoff();
      screen = 0;
    }
  }
  
  if (StickCP2.BtnB.wasReleased()) {
    Serial.println("B Btn Released");
  }

  if(screen == 1) {
    int x = 10;
    int y = 10;
    int lineHeight = 18;

    M5.Lcd.setTextSize(2);
    M5.Lcd.setTextDatum(TL_DATUM);  // coin haut gauche
    M5.Lcd.setTextColor(WHITE, BLACK);  // fond noir, efface proprement
    M5.Lcd.drawString("ID: " + String(id), x, y); y += lineHeight;
    M5.Lcd.drawString("T: " + String(timems) + "ms", x, y); y += lineHeight;
    M5.Lcd.drawString("Roll: " + String(roll, 1) + "     ", x, y); y += lineHeight;
    M5.Lcd.drawString("Pitch: " + String(pitch, 1) + "     ",x, y); y += lineHeight;
    M5.Lcd.drawString("Yaw: " + String(yaw, 1) + "     ", x, y); y += lineHeight;
    M5.Lcd.drawString("Bat: " + String(StickCP2.Power.getBatteryLevel()) + "%          ", x, y); y += lineHeight;
    M5.Lcd.drawString("IP: " + ip, x, y);
  }
  else if(screen == 2) {
    M5.Lcd.setCursor(10, 10);
    M5.Lcd.setTextColor(WHITE, BLACK);
    if(id < 1000) {
      M5.Lcd.setTextSize(10);
    }
    else {
      M5.Lcd.setTextSize(8);
    }
    M5.Lcd.println(id);
  }
  else if(screen == 3) {
    M5.Lcd.setTextSize(8);
    M5.Lcd.setCursor(10, 10);
    
    if(wifienabled != 0 && !screencolored) {
       M5.Lcd.fillScreen(GREEN);
       screencolored = true;
    }
    else if(!screencolored)  {
       M5.Lcd.fillScreen(RED);
       screencolored = true;      
    }
    
    //si le bouton est pressé plus d'une seconde, change la config wifi et inhibe le bouton pour 1s
    if (StickCP2.BtnB.pressedFor(1000)) {
      if(wifienable) {
        wifienable = false;
      }
      numwifi = numwifi + 1;
      numwifi = numwifi % nbwifi;
      btnbactivate = false;
      M5.Lcd.fillScreen(GOLD);
      delay(1000); // pour un seul incrément
      M5.Lcd.fillScreen(RED);
    }

    if (StickCP2.BtnB.wasReleased() && btnbactivate) {
      if(!wifienable) {
        wifienable = true;
      }
      else {
        wifienable = false;
      }
      screencolored = false;
    }

    if (StickCP2.BtnB.releasedFor(1000)) {
      btnbactivate = true;
    }
    M5.Lcd.setTextColor(WHITE);
    M5.Lcd.println("WiFi");
    M5.Lcd.setTextSize(3);
    M5.Lcd.println(ssid[numwifi]);
    
  }
  else if(screen == 4) {
    M5.Lcd.setTextSize(6);
    M5.Lcd.setTextColor(BLACK);
    M5.Lcd.setCursor(10, 10);
    
    if(recordstarted != 0 && !screencolored) {
       M5.Lcd.fillScreen(GREEN);
       screencolored = true;
    }
    else if(!screencolored)  {
       M5.Lcd.fillScreen(RED);
       screencolored = true;      
    }
    M5.Lcd.println("Record");   
    
    if (StickCP2.BtnB.wasReleased()) {
      if(!recordstarted) {
        //String code = generateRandomCode();  // ex: "12-34-56-78"
  sprintf(NumDate, "%04d%02d%02dT%02d%02d%02d",  dt.date.year, dt.date.month, dt.date.date, dt.time.hours, dt.time.minutes,dt.time.seconds);
  String code = NumDate;
        snprintf(filename, sizeof(filename), "/%s.csv", code.c_str());

        Serial.printf("Fichier : %s\n", filename);
        logFile = SPIFFS.open(filename, FILE_WRITE);
        if (!logFile) {
          Serial.println("Erreur ouverture fichier");
          return;
        }
        recordstarted = true;
        id = 0;
      }
      else {
        logFile.flush();
        logFile.close();
        recordstarted = false;
      }
      screencolored = false;
    }

    if(recordstarted) {
      M5.Lcd.setTextSize(2);
      M5.Lcd.println(filename);
    }
 
  }
  else if(screen == 5) {
    M5.Lcd.setCursor(10, 10);
    M5.Lcd.setTextSize(1);
    M5.Lcd.setTextColor(WHITE, BLACK);
    size_t total = SPIFFS.totalBytes();
    size_t used  = SPIFFS.usedBytes(); 
    M5.Lcd.println("== Info SPIFFS ==");
    M5.Lcd.print("Total : ");  
    M5.Lcd.print(total);
    M5.Lcd.println(" octets");
    M5.Lcd.print("Used : ");
    M5.Lcd.print(used);
    M5.Lcd.println(" octets");
    M5.Lcd.print("Free : ");
    M5.Lcd.print(total - used);
    M5.Lcd.println(" octets");
    if (StickCP2.BtnB.wasReleased()) {
      Serial.println("Formatting SPIFFS...");
      M5.Lcd.println("Formatting SPIFFS...");
      SPIFFS.format();
    }
  }
  else if(screen == 6) {
    M5.Lcd.setCursor(10, 10);
    if(wifienabled == 2){
      if (StickCP2.BtnB.wasReleased()) {
        SyncNTP();
        M5.Lcd.setTextColor(BLACK, GREEN);
        boolsyncNTP = true;
      }
      else if(boolsyncNTP){
        M5.Lcd.fillRect(0, 0, 250, 10, GREEN);
        M5.Lcd.fillRect(0, 10, 10, 24, GREEN);
        M5.Lcd.fillRect(60, 10, 190, 24, GREEN);
        M5.Lcd.setTextColor(BLACK, GREEN);
      }
      else {
        M5.Lcd.fillRect(0, 0, 250, 10, ORANGE);
        M5.Lcd.fillRect(0, 10, 10, 24, ORANGE);
        M5.Lcd.fillRect(60, 10, 190, 24, ORANGE);
        M5.Lcd.setTextColor(WHITE, ORANGE);
      }
    }
    else if(!screencolored)  {
      M5.Lcd.fillRect(0, 0, 250, 10, RED);
      M5.Lcd.fillRect(0, 10, 10, 24, RED);
      M5.Lcd.fillRect(60, 10, 190, 24, RED);
      M5.Lcd.setTextColor(WHITE, RED);     
    }
    M5.Lcd.setTextSize(3);
    M5.Lcd.println("NTP");
    M5.Lcd.setTextColor(WHITE, BLACK);
    M5.Lcd.println("RTC UTC :");
    StickCP2.Display.printf("%04d/%02d/%02d\n", dt.date.year, dt.date.month, dt.date.date);
    StickCP2.Display.printf("%02d:%02d:%02d\n", dt.time.hours, dt.time.minutes,dt.time.seconds);
    Serial.printf("RTC   UTC  :%04d/%02d/%02d %02d:%02d:%02d\n",
    dt.date.year, dt.date.month, dt.date.date,
    dt.time.hours, dt.time.minutes,dt.time.seconds);
  }
  
  if (doConnect == true) {
    if (connectToServer()) {
      Serial.println("We are now connected to the BLE Server.");
    } else {
      Serial.println("We have failed to connect to the server; there is nothing more we will do.");
    }
    doConnect = false;
  }
  if (!connected && !doConnect && !doScan) {
    Serial.println("BLE non connecté, tentative de reconnexion...");
    BLEScan* pBLEScan = BLEDevice::getScan();
    pBLEScan->setAdvertisedDeviceCallbacks(new MyAdvertisedDeviceCallbacks());
    pBLEScan->setInterval(1349);
    pBLEScan->setWindow(449);
    pBLEScan->setActiveScan(true);
    pBLEScan->start(5, nullptr, false); // Scan 5 secondes sans blocage
    doScan = true;
  } 
  if(millis() - lastBLEAttempt >= 10000 && !connected && !doConnect && doScan) {
    lastBLEAttempt = millis();
    doScan = false;
  }

  if(recordstarted) {
    if(millis() - lastRecord >= 100) {
      id++;
      lastRecord = millis();
      logFile.printf("%lu,%d,%.2f,%.2f,%.2f\n", timems, id, pitch, roll, yaw);
      if(id % 10 == 0) {
        logFile.flush();
      }
    }
    
  }

  if(wifienable && wifienabled == 0) {
    wifienabled = 1;     
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid[numwifi], password[numwifi]);
    Serial.print("Connexion Wi-Fi");
  }
  else if(wifienabled == 1 && millis() - lastWifiAttempt >= 500) {
    if(WiFi.status() != WL_CONNECTED) {
      Serial.print(".");
      lastWifiAttempt = millis();
    }
    else {
      Serial.println("\nConnecté à : " + WiFi.SSID());
      Serial.println("Adresse IP : " + WiFi.localIP().toString());
      ip = WiFi.localIP().toString();
  
      server.on("/", handleRoot);
      server.on("/download", handleDownload);

      server.begin();
      Serial.println("Serveur HTTP lancé");

      wifienabled = 2;
      //ici bouton C pour ntp
    }
  }
  else if(!wifienable && wifienabled != 0) {
    server.close();         // Ferme la socket
    server.stop();          // Libère les ressources (non toujours nécessaire)
    Serial.println("Serveur HTTP desactivé");
    WiFi.disconnect(true);  // true = oublie aussi les identifiants enregistrés
    WiFi.mode(WIFI_OFF);    // coupe le Wi-Fi complètement
    Serial.println("Wifi desactivé");
    ip = "";
    wifienabled = 0;
  }
  else if(wifienabled == 2) {
    server.handleClient();
  }
}  
