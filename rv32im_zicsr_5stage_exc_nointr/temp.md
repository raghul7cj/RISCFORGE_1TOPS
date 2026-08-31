### **qn 1**
In the circuit shown below, the diodes are ideal with a forward drop of \\(0.7\text{ V}\\). If \\(V_1 = V_2 = 10 \cdot u(t)\\) and \\(V_3 = 3 \cdot u(t)\\), what is the time constant of the capacitor charging in seconds? [cite: 67]

#### **if any diagram**
```
            V3
            |
          [12 Ohm]
            |
  V1 ----[12 Ohm]---->|----+----[12 Ohm]----|<---- V2
                           |
                          [C] (Capacitor)
                           |
                          [12 Ohm]
                           |
                          GND
``` [cite: 67]

#### **options**
*   **A)** 3
*   **B)** 6
*   **C)** 12
*   **D)** 4 [cite: 67]

---

### **qn 2**
The voltage source in the circuit shown below is described by \\(V(t) = V_1 \cdot u(t)\\). What is the steady state value of the voltage across \\(L_2\\) if: \\(V_1 = 1\text{ V}\\), \\(R_1 = 100\ \Omega\\), \\(L_1 = 3\text{ nH}\\), and \\(L_2 = 1\text{ nH}\\)? [cite: 78]

#### **if any diagram**
```
                +-----[ R1 ]-----+
                |                |
     V(t) ------+-----[ L1 ]-----+-----[ L2 ]----- GND
                                 |
                               V_L2
``` [cite: 78]

#### **options**
*   **A)** \\(0.25\text{ V}\\) [cite: 78]
*   **B)** \\(1.00\text{ V}\\) [cite: 78]
*   **C)** \\(0.00\text{ V}\\) [cite: 78]
*   **D)** \\(0.75\text{ V}\\) [cite: 78]

---

### **qn 3**
The switch closes at \\(t=0\\). What is the instantaneous voltage jump observed at the output node \\(V_{\text{out}}\\)? Assume capacitor \\(C_1\\) is initially charged to \\(0\text{ V}\\) (\\(C_1 = 2\text{ F}\\)), resistor \\(R_1 = 1\ \Omega\\), and capacitor \\(C_2\\) is initially charged to \\(2\text{ V}\\). [cite: 74]

#### **if any diagram**
```
          S1 (closes at t=0)
   1V o------\  /------[ C1 ]------+----- Vout
                                   |
                                  [R1]
                                   |
                                  [C2] (Initially 2V)
                                   |
                                  GND
``` [cite: 74]

#### **options**
*   **A)** 2 Volts [cite: 74]
*   **B)** -1 Volts [cite: 74]
*   **C)** 0 Volts [cite: 74]
*   **D)** 1 Volts [cite: 74]

---

### **qn 4**
In the circuit below, the ideal switch is turned on at \\(t=0\\) and turned off at \\(t=1\text{ s}\\). What is the inductor current at \\(t=2\text{ s}\\) if the diode has a forward drop of \\(1\text{ V}\\)? [cite: 71]

#### **if any diagram**
```
          3V
          |
        [0.5H] Inductor
          |
          +-------+-------+
          |       |       |
         [S]     _|_     [ ] 1 Ohm
        Switch   \ /     [ ]
         (t=0)    v       |
          |       |       |
         GND     GND     GND
``` [cite: 71]

#### **options**
*   **A)** 6 A [cite: 71]
*   **B)** 9 A [cite: 71]
*   **C)** 10 A [cite: 71]
*   **D)** 5 A [cite: 71]

---

### **qn 5**
You are working on the following op-amp circuit having power supplies \\(+15\text{ V}\\) and \\(-15\text{ V}\\). If the frequency of the sinusoidal input is \\(500\text{ Hz}\\), what will be the output voltage \\(V_{\text{out}}\\) of the op-amp? [cite: 89]

#### **if any diagram**
```
                10 kOhm
          +------[ ]------+
          |               |
          +-----\         |
  1 kOhm         |-\      |
  --[ ]--+------>|  \-----+---- Vout
         |       |   |
        (1V)     |   | (Dual Supply: +/-15V)
         |       |   |
  1 kOhm |       |   |
  --[ ]--+------>|  /
         |       |/
       (0.1V~)
``` [cite: 89]

#### **options**
*   **A)** -15 V [cite: 88]
*   **B)** -0.7 V [cite: 88]
*   **C)** 0.7 V [cite: 88]
*   **D)** 15 V

---

### **qn 6**
In the circuit shown below, what should be the value of feedback resistor \\(R_1\\) for the closed-loop system to be unconditionally stable? Assume \\(R_2 = 1000\ \Omega\\) and \\(R = 200\ \Omega\\). [cite: 81]

#### **if any diagram**
```
                 R2
           +----[ ]----+
           |           |
  Vin -----\           |
            |-\        |
            |  \-------+----- Vout
            |  /
         +->|/
         |
        [R1]
         |
        GND
``` [cite: 81]

#### **options**
*   **A)** \\(R_1 = 1000\ \Omega\\) [cite: 81]
*   **B)** \\(R_1 > 1000\ \Omega\\) [cite: 81]
*   **C)** None of the given options [cite: 81]
*   **D)** \\(R_1 < 1000\ \Omega\\) [cite: 81]

---

### **qn 7**
In the circuit below, \\(R_1 = 1\text{ kOhm}\\), \\(R_2 = 3\text{ kOhm}\\), \\(R_3 = 2\text{ kOhm}\\), and \\(V_1 = 5\text{ V}\\). Calculate the voltage in Volts at node **X** if current source \\(I_1 = 2\text{ mA}\\) and current source \\(I_2 = 5\text{ mA}\\). [cite: 73]

#### **if any diagram**
```
          R1        X
   +-----[ ]--------+--------+
   |                |        |
  (v) I1           [ ] R3   [ ] R2
   |                |        |
  (+) V1           (v) I2    |
   |                |        |
  GND              GND      GND
``` [cite: 73]

#### **options**
*   **A)** -21 V [cite: 73]
*   **B)** 5 V [cite: 73]
*   **C)** 6 V [cite: 73]
*   **D)** 0 V [cite: 73]

---

### **qn 8**
Determine the mathematical gain expression (\\(V_{\text{out}} / V_{\text{in}}\\)) for the non-ideal op-amp configuration represented below. [cite: 99]

#### **if any diagram**
```
   Vin ----( + )-----\
            |         |-\
            |         |  \----+----- Vout
            +--[ R1 ]-|  /    |
                      |/     [ ] R2
                              |
                             GND
``` [cite: 99]

#### **options**
*   **A)** \\(\frac{R_2}{R_1}\\) [cite: 99]
*   **B)** \\(-\frac{R_2}{R_1}\\) [cite: 99]
*   **C)** \\(1 - \frac{R_2}{R_1}\\) [cite: 99]
*   **D)** \\(1 + \frac{R_2}{R_1}\\) [cite: 102]

---

### **qn 9**
Find the operating regions of the four independent MOS transistor circuits shown below. Assume the threshold voltage of the PMOS transistor is \\(V_{TP} = -0.4\text{ V}\\). [cite: 100]

#### **if any diagram**
```
      (a)              (b)              (c)              (d)
     +VDD             +VDD             +VDD             +VDD
      |                |                |                |
     --- PMOS         --- PMOS         --- PMOS         --- PMOS
  2V -| o-           -| o-            -| o-            -| o-
     \ /_             \ /_             \ /_             \ /_
      |                |                |                |
      +---> 2V         +---> 0.3V       +---> 1V         +---> 0.6V
      |                |                |                |
     GND              GND              GND              GND
``` [cite: 100]

#### **options**
*   **A)** OFF, OFF, OFF, OFF [cite: 100]
*   **B)** OFF, Triode, Saturation, Triode [cite: 100]
*   **C)** OFF, OFF, Saturation, OFF [cite: 100]
*   **D)** Saturation, Triode, OFF, OFF [cite: 100]

---

### **qn 10**
What is the minimum required gain per stage (represented as \\(-A\\)) in the three-stage ring amplifier circuit below to make the output oscillate? [cite: 95]

#### **if any diagram**
```
     +-----------------------------------------+
     |                                         |
     v                                         |
  +----+       +----+       +----+             |
  | -A |------>| -A |------>| -A |-----+------>+
  +----+       +----+       +----+     |
                                       v
                                      OUT
``` [cite: 95]

#### **options**
*   **A)** 2 [cite: 95]
*   **B)** \\(\sqrt{2}\\) [cite: 95]
*   **C)** \\(\sqrt{3}\\) [cite: 95]
*   **D)** Will oscillate for any gain [cite: 95]

---

### **qn 11**
What is the equivalent small-signal output resistance \\(R_{\text{out}}\\) looking into the terminal of the active load configuration shown below? [cite: 96]

#### **if any diagram**
```
          VDD
           |
          (v) I1 (Current Source)
           |
           +----- Rout
           |
          [R1]
           |
         |/ Q2 (Gate connected to Drain)
         |\_
           |
          GND
``` [cite: 96]

#### **options**
*   **A)** \\(1/g_{m2}\\) [cite: 96]
*   **B)** \\(R_1 + \left[(1/g_{m2}) \parallel r_{o2}\right]\\) [cite: 96]
*   **C)** \\(\infty\\) [cite: 96]
*   **D)** \\(R_1 + 1/g_{m2} + r_{o2}\\) [cite: 96]

---

### **qn 12**
In the active MOS differential amplifier stage below, identify what kind of amplifier configuration transistors \\(M_1\\) and \\(M_2\\) function as, respectively. [cite: 97]

#### **if any diagram**
```
                   VDD       VDD
                    |         |
                    |        [RD]
                    |         |
                    |         +----- Vout
                    |         |
         Vin o----|/ M1     |\| M2 o---- Vb
                  |\_         _/|
                    |         |
                    +----+----+
                         |
                        (v) I1 (Current Source)
                         |
                        GND
``` [cite: 97]

#### **options**
*   **A)** CS, CS (Common Source, Common Source) [cite: 97]
*   **B)** CD, CG (Common Drain, Common Gate) [cite: 97]
*   **C)** CD, CS (Common Drain, Common Source) [cite: 97]
*   **D)** CG, CG (Common Gate, Common Gate) [cite: 97]

---

⏱️ **Would you like to try a timed diagnostic challenge containing these 12 questions to verify your execution speed, or should we compile another specific deck of hardware programming and digital RTL verification questions?**### **qn 1**

If a Fullwave Bridge rectifier with a supply of \\(5 \text{ V}*{\text{pk}}\\) and \\(50\text{ Hz}\\) supply has \\(\Delta V*{\text{out}} = 2\text{ V}\\) and \\(V\_{\text{out}} = 8\text{ V}\\), if the smoothing capacitor is \\(1\text{ mF}\\), then what is the required load resistance? [cite: 7]

#### **if any diagram**

````
      +---|>|---+--------+
      |   D1    |        |
(~)--+         +--[C]--[R_L] (Load)
      |   D2    |        |
      +---|<|---+--------+
``` [cite: 7]

#### **options**
*   **A)** \\(34.89\ \Omega\\) [cite: 7]
*   **B)** \\(112.7\ \Omega\\) [cite: 7]
*   **C)** \\(100\ \Omega\\) [cite: 7]
*   **D)** \\(40\ \Omega\\) [cite: 7]

---

### **qn 2**
A pn junction has a diffusion capacitance of \\(9\text{ nF}\\). If the junction is biased at \\(1\text{ V}\\) and \\(V_t\\) threshold = \\(0.0259\text{ V}\\), with equal minority carrier lifetime in both regions of \\(1.2\ \mu\text{s}\\), then what is the DC bias current? [cite: 12]

#### **if any diagram**
*(No diagram required)*

#### **options**
*   **A)** \\(1\text{ mA}\\) [cite: 12]
*   **B)** \\(0.3885\text{ mA}\\) [cite: 12]
*   **C)** \\(0.2779\text{ mA}\\) [cite: 12]
*   **D)** \\(0.5923\text{ mA}\\) [cite: 12]

---

### **qn 3**
A Colpitt's oscillator is oscillating at \\(325\text{ Hz}\\). If \\(L = 1\text{ mH}\\) and \\(C_1 = 1\ \mu\text{F}\\), what is the value of \\(C_2\\)? [cite: 13, 25]

#### **if any diagram**

````

```
       +---- C1 ----+
       |            |

```

L ------+--- Out     +----> |            | +---- C2 ----+

```

#### **options**
*   **A)** \\(0.315\ \mu\text{F}\\) [cite: 13, 25]
*   **B)** \\(0.315\text{ F}\\) [cite: 13, 25]
*   **C)** \\(1\ \mu\text{F}\\) [cite: 13, 25]
*   **D)** \\(1\text{ F}\\) [cite: 13, 25]

---

### **qn 4**
An \\(n\\)-bit binary weighted DAC can be designed as shown in the figure. An 8-bit DAC is designed similarly and is provided with a digital input equivalent to \\(34\text{H}\\). If the resistor connected to the LSB is \\(2\text{ K}\Omega\\) and \\(V_{\text{ref}} = 7.8\text{ V}\\), find the analog output current (in \\(\text{mA}\\)). [cite: 23]

#### **if any diagram**

```

```
Uref
 |
---  2R    4R    8R    16R     R_FB = R
 |---[ ]---[ ]---[ ]---[ ]-----+-----+
 |                             |     |
GND    s3    s2    s1    s0    |   -\|  Op-amp
       |     |     |     |     +-----\+----------> Analog Output
     [   Control Circuit  ]          /

```

```

#### **options**
*   **A)** \\(0.79\text{ mA}\\) [cite: 23]
*   **B)** \\(1.1\text{ mA}\\) [cite: 23]
*   **C)** \\(0.92\text{ mA}\\) [cite: 23]
*   **D)** \\(0.56\text{ mA}\\) [cite: 23]

---

### **qn 5**
For an inverting amplifier using an OPAMP, the feedback resistor \\(R_f\\) is \\(100\text{ K}\Omega\\) and \\(R_1 = 10\text{ K}\Omega\\). The non-inverting input of the Op-Amp is grounded through a \\(10\text{ K}\Omega\\) resistor. If the input offset voltage is \\(1.689\text{ mV}\\) and the input offset current is \\(103.67\text{ nA}\\), what is the total output voltage offset? [cite: 29]

#### **if any diagram**
*(No diagram required)*

#### **options**
*   **A)** \\(13.29\text{ mV}\\) [cite: 29]
*   **B)** \\(32.73\text{ mV}\\) [cite: 29]
*   **C)** \\(28.96\text{ mV}\\) [cite: 29]
*   **D)** \\(2.79\text{ mV}\\) [cite: 29]

---

### **qn 6**
Let us assume the value of \\(R=1\text{ K}\Omega\\) and that of the capacitor \\(C = 1\ \mu\text{F}\\). What will be the wave shape and its peak amplitude of the output waveform when a square periodic wave of peak value 5V is applied to an ideal inverting integrator? [cite: 31]

#### **if any diagram**

```

```
          C
     +---| |---+
     |         |

```

Vin ---[R]---\   | |--+---> Vo +-|+/ | GND

```

#### **options**
*   **A)** Triangular wave, peak value \\(5\text{ V}\\) [cite: 31]
*   **B)** Triangular wave, peak value \\(-2.5\text{ V}\\) [cite: 31]
*   **C)** Square wave, peak value \\(-2.5\text{ V}\\) [cite: 31]
*   **D)** Saw tooth wave, peak value \\(-2.5\text{ V}\\) [cite: 31]

---

### **qn 7**
A 4-bit binary weighted resistor DAC has \\(R_f = 1\text{ K}\Omega\\) and \\(R = 10\text{ K}\Omega\\) and is used for conversion of the digital value \\(1011\\) into an analog voltage. Due to a technical fault in the circuit, the bit values changed such that bit \\(b_1 = 0\\) and \\(b_2 = 1\\). Find the absolute difference between the expected value and the value produced by this DAC. [cite: 62]

#### **if any diagram**
*(No diagram required)*

#### **options**
*   **A)** \\(0.32\text{ V}\\) [cite: 62]
*   **B)** \\(0.1\text{ V}\\) [cite: 62]
*   **C)** \\(0.14\text{ V}\\) [cite: 62]
*   **D)** \\(0.2\text{ V}\\) [cite: 62]

---

### **qn 8**
In the circuit shown in the figure, what is the approximate value of the collector-to-emitter voltage \\(V_{CE}\\) if \\(V_{BE}\\) for the BJT is \\(1\text{ V}\\), \\(R_1 = R_2 = 1\text{ K}\Omega\\), \\(R_3 = 200\text{ K}\Omega\\), and \\(V_{DD} = 5\text{ V}\\)? Assume \\(\beta = 100\\). [cite: 82]

#### **if any diagram**

```

```
            VDD (5V)
             |
             +---+--- [R2] --- Collector
             |   |
            [R3] |   | /
             |   +---|   NPN Transistor
             |       | \
             |         v
             |       Emitter
             |         |
             +--------[R1]
                       |
                      GND

```

```

#### **options**
*   **A)** \\(3.5\text{ V}\\) [cite: 82]
*   **B)** \\(2\text{ V}\\) [cite: 82]
*   **C)** \\(3\text{ V}\\) [cite: 82]
*   **D)** \\(5\text{ V}\\) [cite: 82]

---

### **qn 9**
For the circuit shown, the diode current is given by \\(I_D = K(V_D^2)\\) for \\(V_D > 0\\) and \\(I_D = 0\\) for \\(V_D \le 0\\). Find the current flowing through the parallel resistor if \\(K = 3/5 \text{ A/V}^2\\), \\(R = 1\ \Omega\\), and the source current is \\(I_0 = 5\text{ A}\\). [cite: 83]

#### **if any diagram**

```

```
           +--------+--------+
           |        |        |
          (↑) Io   [R]      [\ ] Diode 1
           |        |       [v ] Diode 2
           |        |        |
           +--------+--------+

```

```

#### **options**
*   **A)** \\(2\text{ A}\\) [cite: 83]
*   **B)** \\(3.33\text{ A}\\) [cite: 83]
*   **C)** \\(1.33\text{ A}\\) [cite: 83]
*   **D)** None of the given options [cite: 83]

---

### **qn 10**
The circuit shown contains a source voltage \\(V_s\\) as shown in the plot, and the resulting current through the circuit is also plotted. Which of the following components, when connected between nodes **a** and **b**, could explain the observed current waveform? [cite: 107]

#### **if any diagram**

```

```
      a         b

```

\---+--[?]--+----[R = 10k]--+ |                       | (Vs)                     | |                       | ---+-----------------------+

Source Voltage Vs plot: 15V  +------+ |      | 0V -+------+------+--- |             | -15V  |             +------+ +-------------+------+ 0     100    200    300 (ms)

Current plot: 1.5mA+--+ |  | 0mA-+  +--\_\_\_ |         \_\_\_\_\_\_\_\_\_\_ -1.5mA+-------------------- 0     100    200    300 (ms)

```

#### **options**
*   **A)** A forward-biased diode pointing from **a** to **b** [cite: 107]
*   **B)** A capacitor [cite: 107]
*   **C)** A reverse-biased diode pointing from **b** to **a** [cite: 107]
*   **D)** An NPN transistor [cite: 107]

---

### **qn 11**
For the active network shown below, both buffers are ideal amplifiers with a small-signal gain of \\(G\\). Calculate the equivalent input conductance \\(Y_{\text{in}} = 1/Z_{\text{in}}\\) at an operating frequency of \\(\omega = 1\text{ Grad/sec}\\) if: \\(R = 200\ \Omega\\), \\(C_1 = 2\text{ nF}\\), \\(C_2 = 5\text{ nF}\\), and \\(G = -2\\). [cite: 84]

#### **if any diagram**

```

```
           +-----[Buffer]-----+
           |       Gain=G     |

```

IN ---------+-------[ C1 ]-----+---- [R] ----+ (Zin)       |                  |             | +-----[Buffer]-----+           [C2] Gain=G                   | GND

```

#### **options**
*   **A)** \\(206\text{ S}\\) [cite: 84]
*   **B)** \\(-2\text{ S}\\) [cite: 84]
*   **C)** \\(6\text{ S}\\) [cite: 84]
*   **D)** \\(-4\text{ S}\\) [cite: 84]

---

### **qn 12**
The op-amp in the circuit is ideal and runs off a supply/ground of \\(5\text{ V}/0\text{ V}\\). The op-amp is enabled when the `Enable` pin is set to \\(5\text{ V}\\), and disabled when `Enable` is \\(0\text{ V}\\). When disabled, the output impedance is infinite. Find the voltage at the output node \\(V_o\\) if the input \\(V_{\text{in}} = 3\text{ V}\\) and `Enable` is set to \\(5\text{ V}\\). Assume the forward voltage drop of the diode is \\(0.5\text{ V}\\). [cite: 86]

#### **if any diagram**

```

```
           Enable (5V)
             |
           +---+

```

Vin ----+---| - | (3V)    |   |   |----+----> Vo [ ]  | + |    | |   +---+    | |     |     *|* Diode (0.5V drop) |    GND    \ / |             v +-------------+ | (1mA) Current Source | GND

```

#### **options**
*   **A)** \\(4.0\text{ V}\\) [cite: 86]
*   **B)** \\(0.5\text{ V}\\) [cite: 86]
*   **C)** \\(0.0\text{ V}\\) [cite: 86]
*   **D)** \\(3.5\text{ V}\\)

---

⏱️ **Shall we set up a timed 30-minute practice test using this final batch of Analog & Converter questions to verify your timing and formula retrieval before you review the derivations?**

```


this is  an unclear set of diagrams , try interpreting it , and make similar questions of same concepts and difficulty and proper ascii diagrams and llist in chat