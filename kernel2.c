/* Check if the compiler thinks you are targeting the wrong operating system. */
#if defined(__linux__)
#error "You are not using a cross-compiler, you will most certainly run into trouble"
#endif

/* This code will only work for the 32-bit ix86 targets. */
#if !defined(__i386__)
#error "This code needs to be compiled with a ix86-elf compiler"
#endif

#define VGA_ADDRESS 0xB8000
#define VGA_BUFFER ((volatile unsigned short*)VGA_ADDRESS)

unsigned char inb(unsigned short port) {
    unsigned char result;
    asm volatile("inb %1, %0" : "=a"(result) : "Nd"(port));
    return result;
}

int cursor_x = 0;
int cursor_y = 0;

void scroll() {
    // Simple scrolling: move lines up
    for(int y = 0; y < 24; y++) {
        for(int x = 0; x < 80; x++) {
            VGA_BUFFER[y * 80 + x] = VGA_BUFFER[(y + 1) * 80 + x];
        }
    }
    // Clear last line
    for(int x = 0; x < 80; x++) {
        VGA_BUFFER[24 * 80 + x] = 0x0700 | ' ';
    }
    cursor_y = 24;
}

void print_char(char c) {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y++;
    } else {
        VGA_BUFFER[cursor_y * 80 + cursor_x] = (0x0F << 8) | c;
        cursor_x++;
    }

    if (cursor_x >= 80) {
        cursor_x = 0;
        cursor_y++;
    }
    if (cursor_y >= 25) {
        scroll();
    }
}

void print_string(const char* str) {
    while (*str) {
        print_char(*str++);
    }
}

void clear_screen() {
    for (int i = 0; i < 80 * 25; i++) {
        VGA_BUFFER[i] = (0x07 << 8) | ' ';
    }
    cursor_x = 0;
    cursor_y = 0;
}

int shift_active = 0;

char scan_code_map[128] = {
    0,  27, '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '\b', /* Backspace */
    '\t', 'q', 'w', 'e', 'r', 't', 'y', 'u', 'i', 'o', 'p', '[', ']', '\n', /* Enter */
    0, 'a', 's', 'd', 'f', 'g', 'h', 'j', 'k', 'l', ';', '\'', '`', 0, /* Left Shift */
    '\\', 'z', 'x', 'c', 'v', 'b', 'n', 'm', ',', '.', '/', 0, /* Right shift */
    '*', 0, ' ', /* Space */
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, /* F1-F10 */
    0, 0, '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '0', '.'
};

// Shifted Map (Shift Held Down)
char scan_code_map_shifted[128] = {
    0,  27, '!', '@', '#', '$', '%', '^', '&', '*', '(', ')', '_', '+', '\b',
    '\t', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '{', '}', '\n',
    0, 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ':', '"', '~', 0,
    '|', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', '<', '>', '?', 0,
    '*', 0, ' ',
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, '7', '8', '9', '-', '4', '5', '6', '+', '1', '2', '3', '0', '.'
};

unsigned char get_scancode() {
    while (1) {
        if (inb(0x64) & 1) {
            return inb(0x60); // Read Data Port
        }
    }
}

char get_char() {
    char c = 0;
    while (c == 0) {
        unsigned char scancode = get_scancode();

        // 1. Handle Shift Press (Make Code)
        // 0x2A = Left Shift, 0x36 = Right Shift
        if (scancode == 0x2A || scancode == 0x36) {
            shift_active = 1;
            continue;
        }

        // 2. Handle Shift Release (Break Code)
        // 0xAA = Left Shift Release, 0xB6 = Right Shift Release
        // (Break code is usually Make Code + 0x80)
        if (scancode == 0xAA || scancode == 0xB6) {
            shift_active = 0;
            continue;
        }

        // 3. Ignore other Key Release codes (High bit set)
        if (scancode & 0x80) continue;

        // 4. Map the key
        if (scancode < 128) {
            if (shift_active) {
                c = scan_code_map_shifted[scancode];
            } else {
                c = scan_code_map[scancode];
            }
        }
    }
    return c;
}

void get_input_string(char* buffer, int max_len) {
    int i = 0;
    while (1) {
        char c = get_char();

        if (c == '\n') {
            print_char('\n');
            break;
        } 
        else if (c == '\b') {
            if (i > 0) {
                i--;
                if (cursor_x > 0) cursor_x--;
                VGA_BUFFER[cursor_y * 80 + cursor_x] = (0x0F << 8) | ' ';
            }
        }
        else if (i < max_len - 1) {
            buffer[i++] = c;
            print_char(c);
        }
    }
    buffer[i] = '\0';
}

void kernel_main() {
    clear_screen();
    print_string("THE KERNEL HAS GAINED LIFE AND IS CURIOUS ABOUT YOUR NAME\n");
    print_string("----------------------------------------------------------\n");

    char buf[32];

    while (1) {
        print_string("\nWhat is your name? Name: ");
        get_input_string(buf, 32);
        
        print_string("Nice! So your name is ");
        print_string(buf);
        print_string(". What a name, huh?!");
        print_string("\n");
        print_string("----------------------------------------------------------\n");
        print_string("But I don't know if I can trust you. Just to confirm, lets do it again...");
    }
}
