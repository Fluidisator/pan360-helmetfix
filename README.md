# 🎯 Project Goal

This project helps users who capture 360° photos from a moving setup (e.g., helmet, backpack...) to correct the horizon level (roll and pitch) of their pictures.

---

# 🔧 Hardware Requirements

## Required Devices

- A 360° camera capable of taking pictures at regular intervals. *(This project was developed using a GoPro Max.)*
- [WT9011DCL BT50 IMU Sensor](https://witmotion-sensor.com/products/wt9011dcl-bluetooth5-0-compact-size-accelerometer-inclinometer-sensor)
- [M5StickC Plus2 ESP32](https://shop.m5stack.com/products/m5stickc-plus2-esp32-mini-iot-development-kit)

## Sensor Mounting

Mount the Witmotion sensor on your helmet, ideally as close to the 360° camera as possible. The sensor should be aligned on the same axis as the camera.

![Mounting Example on helmet](/doc/mounting.png "Mounting on helmet")

---

# 🔌 M5StickC Plus2 Firmware

The firmware source code is located in the `m5stickcplus2_fw/` directory.

### Installation Steps

1. Install the Arduino IDE following the [official M5Stack instructions](https://docs.m5stack.com/en/arduino/m5stickc_plus2/program).
2. Edit the configuration variables (Wi-Fi credentials and Witmotion MAC address).
3. Upload the firmware to the M5Stick.
4. Press the left side button to power on the device.

### M5StickC User Interface

Press the main **M5** button to cycle through the following screens:

1. **Device Status** – Sensor and Wi-Fi information
2. **Recording ID** – Displayed when recording is active
3. **Wi-Fi Control** – Press the right side button to enable
4. **Start/Stop Recording** – Press the right side button to toggle
5. **Filesystem Info** – Press the right side button to format
6. **NTP information** – Time synchronization status
7. **Filesystem Info** – Press the right side button to format


---

# ▶️ How To Use

## Starting a Recording

1. Power on the **M5Stick**.
2. Power on the **Witmotion sensor**.
3. Power on your **360° camera**.
4. Ensure the M5Stick shows pitch, roll, and yaw values.
5. On **Screen 4**, press the right side button to start recording.
6. Show **Screen 2** (recording ID) in front of the camera for later synchronization.

![record id pic](/doc/record_id.png "Record ID pic")

7. When done, press the right side button again on **Screen 4** to stop recording.

---

# 🛠️ 360° Image Correction


## Initial Setup

### Only if you want to fix JPG images (--update_images set to jpeg)

1. Clone this repository:
   ```bash
   git clone git@github.com:qhess34/pan360-helmetfix.git

2. Clone the Img360 Transformer repository:
   ```bash
   git clone git@github.com:Starmania/img360.git

3. Follow the installation guide at: https://github.com/Starmania/img360/tree/master

4. Copy the transformer library to the scripts/ directory:
   ```bash
   cp -r img360/img360_transformer/ pan360-helmetfix/scripts/.

## Fixing the Images

1. Copy your 360° photos to a local folder.

2. Retrieve the M5Stick CSV data:
* Enable Wi-Fi (via Screen 3).
* Find the IP address on Screen 1.
* Open http://<device_ip>/ in your browser to download the CSV file.

3. Identify the image where the recording ID is clearly visible. Keep it memory for the **indexref** parameter, the filename will be the **photoref**

4. Run the correction script:
   ```bash
   ./correct_angles.py \
     --photodir PATH_TO_PHOTOS \
     --recordfile CSV_FILE_FROM_M5STICK \
     --photoref FILENAME_WITH_ID \
     --indexref RECORDING_ID \
     --outputcsv output.csv
     --update_images metadatas
   ```

## 3D configuration settings

As there are plenty of ways to install the camera and the IMU, it is necessary to specify some parameters

### IMU Referencial (x,y,z)

Here is the Witmotion WT9011DCL referencial (left : horizontal configuration / right : vertical configuration)

![witmotion pic](/doc/witmotion.png "Wimotion ref x,y,z")

### GoPro Max referencial

Here is the GoPro Max referentiel 

![gopro max pic](/doc/gopromax.jpg "GoPro Max ref x,y,z")

### Parameters

* --camera_x/y/z : select the IMU axes that are aligned with the camera axes  
* --camera_roll_axis : select the roll axis of the camera (tilt head side to side, ear toward shoulder)  
* --camera_pitch_axis : select the pitch axis of the camera (tilt forward/backward, ground to sky)  
* --camera_yaw_axis : select the yaw axis of the camera (rotation around vertical axis, heading direction)  
* --pitch/roll/yaw_level_ref : specify an angular offset at which the level should be considered 0  


