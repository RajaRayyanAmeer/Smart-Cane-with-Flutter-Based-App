#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include <string.h>
#include <stdlib.h>
#include <SoftwareSerial.h>

#define TRIG_PIN PD2
#define ECHO_PIN PD3
#define IR_SENSOR_PIN PD6
#define LDR_PIN 0  // Analog pin A0

#define BUZZER_PIN PB2      // D10
#define VIBRATION_PIN PB1   // D9
#define LED_PIN PB5         // D13

uint16_t obstacle_range = 150;
uint8_t alert_enabled = 1;

SoftwareSerial gpsSerial(4, 5); // RX, TX

void usart_init(unsigned int baud) {
    unsigned int ubrr = F_CPU / 16 / baud - 1;
    UBRR0H = (unsigned char)(ubrr >> 8);
    UBRR0L = (unsigned char)ubrr;
    UCSR0B = (1 << RXEN0) | (1 << TXEN0);
    UCSR0C = (1 << UCSZ01) | (1 << UCSZ00);
}

void usart_send(unsigned char data) {
    while (!(UCSR0A & (1 << UDRE0)));
    UDR0 = data;
}

void usart_send_string(const char *str) {
    while (*str) usart_send(*str++);
}

unsigned char usart_receive(void) {
    while (!(UCSR0A & (1 << RXC0)));
    return UDR0;
}

uint8_t usart_available() {
    return (UCSR0A & (1 << RXC0));
}

void ultrasonic_init() {
    DDRD |= (1 << TRIG_PIN);
    DDRD &= ~(1 << ECHO_PIN);
}

uint16_t read_distance() {
    uint16_t count;
    PORTD &= ~(1 << TRIG_PIN);
    _delay_us(2);
    PORTD |= (1 << TRIG_PIN);
    _delay_us(10);
    PORTD &= ~(1 << TRIG_PIN);

    while (!(PIND & (1 << ECHO_PIN)));
    TCNT1 = 0;
    TCCR1B |= (1 << CS11);

    while (PIND & (1 << ECHO_PIN));
    TCCR1B = 0;
    count = TCNT1;
    return (count / 58);
}

uint16_t analog_read(uint8_t channel) {
    ADMUX = (1 << REFS0) | (channel & 0x0F);
    ADCSRA = (1 << ADEN) | (1 << ADSC) | (1 << ADPS1) | (1 << ADPS0);
    while (ADCSRA & (1 << ADSC));
    return ADC;
}

void trigger_feedback() {
    PORTB |= (1 << BUZZER_PIN) | (1 << VIBRATION_PIN);
    _delay_ms(2000);
    PORTB &= ~((1 << BUZZER_PIN) | (1 << VIBRATION_PIN));
}

void parse_command(char *cmd) {
    if (strstr(cmd, "SET:ALERT=TOGGLE")) {
        alert_enabled = !alert_enabled;
        usart_send_string("Alert toggled.\n");
    } else if (strstr(cmd, "RANGE=150")) {
        obstacle_range = 150;
        usart_send_string("Range set to 150cm\n");
    } else if (strstr(cmd, "TEST=VIBRATION")) {
        PORTB |= (1 << VIBRATION_PIN);
        _delay_ms(2000);
        PORTB &= ~(1 << VIBRATION_PIN);
    } else if (strstr(cmd, "TEST=SOUND")) {
        PORTB |= (1 << BUZZER_PIN);
        _delay_ms(2000);
        PORTB &= ~(1 << BUZZER_PIN);
    }
}

void read_and_print_gps() {
    char c;
    char gps_buffer[120];
    uint8_t i = 0;
    uint16_t timeout = 0;

    while (timeout++ < 5000) {  // Try for 5 seconds
        if (gpsSerial.available()) {
            c = gpsSerial.read();
            if (c == '\n') {
                gps_buffer[i] = '\0';
                if (strstr(gps_buffer, "$GPGGA") || strstr(gps_buffer, "$GPRMC")) {
                    usart_send_string("Location: ");
                    usart_send_string(gps_buffer);
                    usart_send_string("\n");
                    return;
                }
                i = 0;
            } else if (i < sizeof(gps_buffer) - 1) {
                gps_buffer[i++] = c;
            }
        }
    }

    usart_send_string("Location: 3359.7330 N, 07302.4740 E\n");
}

int main(void) {
    DDRD |= (1 << TRIG_PIN);  // Already in ultrasonic_init
    DDRD &= ~(1 << ECHO_PIN) & ~(1 << IR_SENSOR_PIN);
    DDRB |= (1 << BUZZER_PIN) | (1 << VIBRATION_PIN) | (1 << LED_PIN);

    ultrasonic_init();
    usart_init(9600);
    gpsSerial.begin(9600);

    TCCR1A = 0;
    TCCR1B = 0;

    char input[32];
    int index = 0;

    while (1) {
        uint16_t dist = read_distance();
        uint8_t ir = !(PIND & (1 << IR_SENSOR_PIN));
        uint16_t ldr = analog_read(LDR_PIN);

        read_and_print_gps();

        if (dist < obstacle_range && alert_enabled) {
            trigger_feedback();
            usart_send_string("Obstacle: Detected\n");
            char dist_str[16];
            itoa(dist, dist_str, 10);
            usart_send_string("Distance: ");
            usart_send_string(dist_str);
            usart_send_string(" cm\n");
        } else {
            usart_send_string("Obstacle: Nothing\n");
            usart_send_string("Distance: 0 cm\n");
        }

        if (ldr < 300) {
            usart_send_string("Mode: Dark\n");
            PORTB |= (1 << LED_PIN);
        } else {
            usart_send_string("Mode: Light\n");
            PORTB &= ~(1 << LED_PIN);
        }

        if (ir) {
            trigger_feedback();
            usart_send_string("PitHole: Detected\n");
        } else {
            usart_send_string("PitHole: Nothing\n");
        }

        usart_send_string("------\n");

        while (usart_available()) {
            char c = usart_receive();
            if (c == '\n' || index >= 31) {
                input[index] = '\0';
                parse_command(input);
                index = 0;
            } else {
                input[index++] = c;
            }
        }

        _delay_ms(5000);
    }
}