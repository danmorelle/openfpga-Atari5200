---------------------------------------------------------------------------
-- Atari 5200 top level for the Analogue Pocket (openFPGA)
--
-- Adapted from atari5200top.vhd of the MiSTer Atari800 project:
--   (c) 2013 Mark Watson (original core)
--   MiSTer port by Sorgelig and Wojciech Mostowski
-- Mark Watson's notice applies to the original core files:
--   "I am happy for anyone to use this for non-commercial use.
--    If my vhdl files are used commercially or otherwise sold,
--    please contact me for explicit permission at scrameta (gmail)."
--
-- Pocket changes:
--   * The MiSTer SDRAM controller is removed. Cartridge reads are handed
--     to the Pocket wrapper through a simple request/complete interface
--     (MEM_*), which serves them from block RAM.
--   * The BIOS ROM is supplied by the wrapper (ROM_ADDR / ROM_DATA).
--   * No PS/2 keyboard; the 5200 keypad comes from the JOYn vectors.
---------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use ieee.numeric_std.all;

LIBRARY work;

ENTITY atari5200_pocket IS
PORT
(
	CLK        : IN  STD_LOGIC;   -- 28.636 MHz (16 x 1.79 MHz)
	RESET_N    : IN  STD_LOGIC;

	VGA_VS     : OUT STD_LOGIC;
	VGA_HS     : OUT STD_LOGIC;
	VGA_BLANK  : OUT STD_LOGIC;
	VGA_PIXCE  : OUT STD_LOGIC;
	VGA_B      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
	VGA_G      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
	VGA_R      : OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
	HBLANK     : OUT STD_LOGIC;
	VBLANK     : OUT STD_LOGIC;

	CLIP_SIDES : IN  STD_LOGIC;
	AUDIO_L    : OUT STD_LOGIC_VECTOR(15 downto 0);
	AUDIO_R    : OUT STD_LOGIC_VECTOR(15 downto 0);

	-- Cartridge memory (served by the wrapper)
	MEM_REQUEST  : OUT STD_LOGIC;  -- single cycle pulse
	MEM_COMPLETE : IN  STD_LOGIC;  -- high when idle / done, low while busy
	MEM_WRITE_EN : OUT STD_LOGIC;
	MEM_ADDR     : OUT STD_LOGIC_VECTOR(24 DOWNTO 0);
	MEM_DATA     : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- BIOS ROM (2K)
	ROM_ADDR   : OUT STD_LOGIC_VECTOR(10 DOWNTO 0);
	ROM_DATA   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);

	-- DMA port into the Atari address space (used to fill RAM at boot)
	DMA_REQ    : IN  STD_LOGIC;
	DMA_ADDR   : IN  STD_LOGIC_VECTOR(25 DOWNTO 0);
	DMA_DATA   : IN  STD_LOGIC_VECTOR(7 DOWNTO 0);
	DMA_READY  : OUT STD_LOGIC;

	PAUSE      : IN  STD_LOGIC;
	ATARI_RESET : IN STD_LOGIC;
	CART_SELECT : IN STD_LOGIC_VECTOR(7 DOWNTO 0);

	CPU_HALT   : OUT STD_LOGIC;

	JOY1X      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY1Y      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY2X      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY2Y      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY3X      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY3Y      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY4X      : IN  STD_LOGIC_VECTOR(7 downto 0);
	JOY4Y      : IN  STD_LOGIC_VECTOR(7 downto 0);

	-- Bit layout (active high), same as the MiSTer core:
	--  0 right, 1 left, 2 down, 3 up, 4 fire 1, 5 fire 2, 6 *, 7 #,
	--  8 start, 9 pause, 10 reset, 11..20 keypad 0..9
	JOY1       : IN  STD_LOGIC_VECTOR(20 DOWNTO 0);
	JOY2       : IN  STD_LOGIC_VECTOR(20 DOWNTO 0);
	JOY3       : IN  STD_LOGIC_VECTOR(20 DOWNTO 0);
	JOY4       : IN  STD_LOGIC_VECTOR(20 DOWNTO 0)
);
END atari5200_pocket;

ARCHITECTURE vhdl OF atari5200_pocket IS

SIGNAL KEYBOARD_RESPONSE :  STD_LOGIC_VECTOR(1 DOWNTO 0);
SIGNAL KEYBOARD_SCAN :  STD_LOGIC_VECTOR(5 DOWNTO 0);
signal controller_select : std_logic_vector(1 downto 0);

signal SDRAM_REQUEST : std_logic;
signal SDRAM_REQUEST_COMPLETE : std_logic;
signal SDRAM_READ_ENABLE :  STD_LOGIC;
signal SDRAM_WRITE_ENABLE : std_logic;
signal SDRAM_ADDR : STD_LOGIC_VECTOR(24 DOWNTO 0);
signal SDRAM_DI : STD_LOGIC_VECTOR(31 DOWNTO 0);
signal SDRAM_WIDTH_8bit_ACCESS : std_logic;
signal SDRAM_WIDTH_16bit_ACCESS : std_logic;
signal SDRAM_WIDTH_32bit_ACCESS : std_logic;
signal SDRAM_REFRESH : std_logic;

signal areset_n : std_logic;
signal pause_atari : std_logic;

signal RAM_DATA : std_logic_vector(31 downto 0);

signal JOY1_N_IN : std_logic_vector(4 downto 0);
signal JOY2_N_IN : std_logic_vector(4 downto 0);
signal JOY3_N_IN : std_logic_vector(4 downto 0);
signal JOY4_N_IN : std_logic_vector(4 downto 0);

BEGIN

-- Controller keypad matrix (no PS/2 keyboard on the Pocket)
keyboard_map1 : entity work.ps2_to_atari5200
generic map (ps2_enable => 0, direct_enable => 0)
PORT MAP
(
	CLK => CLK,
	RESET_N => RESET_N,

	JOY1 => JOY1,
	JOY2 => JOY2,
	JOY3 => JOY3,
	JOY4 => JOY4,

	CONTROLLER_SELECT => CONTROLLER_SELECT,

	KEYBOARD_SCAN => KEYBOARD_SCAN,
	KEYBOARD_RESPONSE => KEYBOARD_RESPONSE,

	FKEYS => open
);

-- FRLDU, 0 = pressed
JOY1_N_IN <= not(JOY1(4)&JOY1(0)&JOY1(1)&JOY1(2)&JOY1(3));
JOY2_N_IN <= not(JOY2(4)&JOY2(0)&JOY2(1)&JOY2(2)&JOY2(3));
JOY3_N_IN <= not(JOY3(4)&JOY3(0)&JOY3(1)&JOY3(2)&JOY3(3));
JOY4_N_IN <= not(JOY4(4)&JOY4(0)&JOY4(1)&JOY4(2)&JOY4(3));

atari5200 : entity work.atari5200core_simplesdram
GENERIC MAP
(
	cycle_length => 16,
	video_bits => 8,
	palette => 1,
	internal_rom => 0,
	internal_ram => 16384
)
PORT MAP
(
	CLK => CLK,
	RESET_N => areset_n,

	VIDEO_VS => VGA_VS,
	VIDEO_HS => VGA_HS,
	VIDEO_CS => open,
	VIDEO_BLANK => VGA_BLANK,
	VIDEO_PIXCE => VGA_PIXCE,
	VIDEO_B => VGA_B,
	VIDEO_G => VGA_G,
	VIDEO_R => VGA_R,

	HBLANK => HBLANK,
	VBLANK => VBLANK,

	CLIP_SIDES => CLIP_SIDES,
	AUDIO_L => AUDIO_L,
	AUDIO_R => AUDIO_R,

	JOY1_n => JOY1_N_IN,
	JOY2_n => JOY2_N_IN,
	JOY3_n => JOY3_N_IN,
	JOY4_n => JOY4_N_IN,

	JOY1_X => signed(JOY1X),
	JOY1_Y => signed(JOY1Y),
	JOY2_X => signed(JOY2X),
	JOY2_Y => signed(JOY2Y),
	JOY3_X => signed(JOY3X),
	JOY3_Y => signed(JOY3Y),
	JOY4_X => signed(JOY4X),
	JOY4_Y => signed(JOY4Y),

	KEYBOARD_RESPONSE => KEYBOARD_RESPONSE,
	KEYBOARD_SCAN => KEYBOARD_SCAN,
	CONTROLLER_SELECT => CONTROLLER_SELECT,

	SDRAM_REQUEST => SDRAM_REQUEST,
	SDRAM_REQUEST_COMPLETE => SDRAM_REQUEST_COMPLETE,
	SDRAM_READ_ENABLE => SDRAM_READ_ENABLE,
	SDRAM_WRITE_ENABLE => SDRAM_WRITE_ENABLE,
	SDRAM_ADDR => SDRAM_ADDR,
	SDRAM_DO => RAM_DATA,
	SDRAM_DI => SDRAM_DI,
	SDRAM_32BIT_WRITE_ENABLE => SDRAM_WIDTH_32bit_ACCESS,
	SDRAM_16BIT_WRITE_ENABLE => SDRAM_WIDTH_16bit_ACCESS,
	SDRAM_8BIT_WRITE_ENABLE => SDRAM_WIDTH_8bit_ACCESS,
	SDRAM_REFRESH => SDRAM_REFRESH,

	DMA_FETCH => DMA_REQ,
	DMA_READ_ENABLE => '0',
	DMA_32BIT_WRITE_ENABLE => '0',
	DMA_16BIT_WRITE_ENABLE => '0',
	DMA_8BIT_WRITE_ENABLE => '1',
	DMA_ADDR => DMA_ADDR,
	DMA_WRITE_DATA => x"000000" & DMA_DATA,
	MEMORY_READY_DMA => DMA_READY,

	HALT => pause_atari,
	THROTTLE_COUNT_6502 => "000001", -- 1x CPU speed
	EMULATED_CARTRIDGE_SELECT => CART_SELECT
);

-- Memory requests go straight out to the wrapper
MEM_REQUEST   <= SDRAM_REQUEST;
MEM_WRITE_EN  <= SDRAM_WRITE_ENABLE;
MEM_ADDR      <= SDRAM_ADDR;
SDRAM_REQUEST_COMPLETE <= MEM_COMPLETE;

ROM_ADDR <= SDRAM_ADDR(10 downto 0);

-- BIOS lives at a fixed place in the "SDRAM" map (same decode as MiSTer)
RAM_DATA <= x"FFFFFF"&ROM_DATA  when SDRAM_ADDR(24 downto 14) = "00111000001"  else
            (others=>'1')       when SDRAM_ADDR(24 downto 20) = "00111" else
            x"FFFFFF"&MEM_DATA;

areset_n    <= RESET_N and not(ATARI_RESET);
pause_atari <= PAUSE;
CPU_HALT    <= pause_atari;

END vhdl;
