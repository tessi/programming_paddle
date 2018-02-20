#define USE_HSV
#define LEDCount 24
#define LEDOutputPin 9
#define SerialCommandSize 4

#include "Keyboard.h"
#include <WS2812.h>

WS2812 LED(LEDCount);

int x = 0;
int lastSent = 0;
int sendValue = 0;
unsigned char serialCommandBuffer[SerialCommandSize];
cRGB color;

void setup() {
  pinMode(A0, INPUT);

  LED.setOutput(LEDOutputPin);
  LED.setColorOrderRGB();
  int i = 0;
  color.SetHSV(0, 0, 0);
  while(i < LEDCount) {
    LED.set_crgb_at(i, color);
    i++;
  }
  LED.sync();

  Serial.begin(9600);
  Keyboard.begin();
}

void setLED() {
  if (Serial) {
    if(Serial.available() >= SerialCommandSize) {
      Serial.readBytes(serialCommandBuffer, SerialCommandSize);
      color.SetHSV(serialCommandBuffer[1], serialCommandBuffer[2], serialCommandBuffer[3]);
      LED.set_crgb_at(serialCommandBuffer[0], color);
      LED.sync();
      delay(10);
    }
  }
}

void printValue(int value) {
  String output = String("{") +
                    "\"value\": " + value + ", " +
                    "\"time\": " + millis() +
                  "}";
  Serial.println(output);
  Serial.flush();
}

void pressCmdP() {
  // Keyboard.press(KEY_LEFT_CTRL);
  Keyboard.press('p');
  delay(100);
  Keyboard.releaseAll();
}

void pressCmdShiftP() {
  // Keyboard.press(KEY_LEFT_CTRL);
  Keyboard.press(KEY_LEFT_SHIFT);
  Keyboard.press('P');
  delay(100);
  Keyboard.releaseAll();
}

int keyWasPressed = 0;
int halfTriggerTime = 0;
void pressKeys(int value) {
  if (value < 200) {
    keyWasPressed = 0;
    halfTriggerTime = 0;
  } else {
    if (keyWasPressed > 0) { return; }
    if (value > 400) {
      if (halfTriggerTime == 0) {
        halfTriggerTime = millis();
      }
      if (value > 900) {
        keyWasPressed = 1;
        pressCmdShiftP();
      } else {
        if (abs(millis() - halfTriggerTime) > 800) {
          keyWasPressed = 1;
          pressCmdP();
        }
      }
    }
  }
}

void loop() {
  setLED();

  x = analogRead(A0);
  sendValue = x;
  if (abs(sendValue - lastSent) >= 4) {
    printValue(sendValue);
    lastSent = sendValue;
  }

  pressKeys(sendValue);
}

