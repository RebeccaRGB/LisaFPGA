// A stub for the ESFloppy onboard the LisaFPGA PCB
// This is a placeholder until the real ESFloppy firmware is ready
// All it does is sit idle until the user hits one of the three interface buttons (LEFT, SEL, RIGHT)
// When a button is pressed, it lights up the OLED with a "ESFloppy Not Yet Implemented" message and turns on the activity LED
// Then everything goes back to sleep 5 seconds later

#include <Arduino.h>
#include <Adafruit_SH110X.h>

// Time to do pin definitions for the necessary ESFloppy signals; all we need are the buttons, the activity LED, and the OLED pins
// The left, select, and right buttons; I connected them to the FPGA and then the FPGA to the ESP, so these are actually passthroughs from the FPGA
#define LEFT 34
#define SEL 35
#define RIGHT 36
// The activity LED
#define ACT_LED 1
// The I2C pins for the OLED
#define OLED_SDA 46
#define OLED_SCL 2

// Create the OLED display object; we want a 128x64 display
Adafruit_SH1106G display = Adafruit_SH1106G(128, 64, &Wire, -1);

void setup () {
    Serial.begin(115200); // Open the serial port for debugging, just in case
    Wire.begin(OLED_SDA, OLED_SCL); // Start the I2C bus for the OLED
    display.begin(0x3C, true); // And init it
    // Clear the display since there might be garbage on it after reset
    display.clearDisplay();
    display.display();

    // Set the button pins as inputs
    pinMode(LEFT, INPUT_PULLUP);
    pinMode(SEL, INPUT_PULLUP);
    pinMode(RIGHT, INPUT_PULLUP);

    // And set the activity LED pin as an output and turn it off
    pinMode(ACT_LED, OUTPUT);
    digitalWrite(ACT_LED, LOW);
}

void loop () {
    // In our main loop, we just check if any of the buttons are pressed
    if (digitalRead(LEFT) == LOW || digitalRead(SEL) == LOW || digitalRead(RIGHT) == LOW) {
        // If a button is pressed, turn on the activity LED and display the "not implemented" message
        digitalWrite(ACT_LED, HIGH);
        display.clearDisplay();
        display.setTextSize(2);
        display.setTextColor(SH110X_WHITE);
        display.setCursor(0, 0);
        display.println("ESFloppy");
        display.println("Not Yet");
        display.println("Working...");
        display.println("Sorry!");
        display.display();

        delay(5000); // Hold the message for 5 seconds

        // Once the 5 seconds are up, turn off the activity LED and clear the OLED again
        digitalWrite(ACT_LED, LOW);
        display.clearDisplay();
        display.display();
    }
}