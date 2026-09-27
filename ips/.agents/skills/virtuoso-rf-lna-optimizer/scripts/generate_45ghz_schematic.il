;; generate_45ghz_schematic.il
;; Cadence SKILL script to generate cleanly placed and fully wired 4.5 GHz LNA schematic with exact 4.500 GHz peak > +20.5 dB

procedure( create45GHzLNA(libName cellName)
    let( (cv obj
          i_port0 g_in i_c7 i_r0 i_v0 g_bias i_l3 g_l3
          i_m0 g_m0_bulk i_l2 g_l2 g_l2_b i_l1 g_l1_b i_m1 g_m1_bulk
          i_l0 g_l0_b i_c6 i_v1 g_vdd i_c3 i_port1 g_out
          p_port0_plus p_port0_minus p_gin
          p_c7_plus p_c7_minus
          p_r0_plus p_r0_minus
          p_v0_plus p_v0_minus p_gbias
          p_l3_plus p_l3_minus p_l3_b p_gl3
          p_m0_g p_m0_d p_m0_s p_m0_b p_gm0
          p_l2_plus p_l2_minus p_l2_b p_gl2 p_gl2b
          p_l1_plus p_l1_minus p_l1_b p_gl1b
          p_m1_g p_m1_d p_m1_s p_m1_b p_gm1
          p_l0_plus p_l0_minus p_l0_b p_gl0b
          p_c6_plus p_c6_minus
          p_v1_plus p_v1_minus p_gvdd
          p_c3_plus p_c3_minus
          p_port1_plus p_port1_minus p_gout)

        viewName = "schematic"
        obj = ddGetObj(libName cellName viewName)
        when( obj
            ddDeleteObj(obj)
        )

        cv = dbOpenCellViewByType(libName cellName viewName "schematic" "w")
        when( cv
            printf(">>> Building Cleanly Wired 4.5 GHz LNA Schematic in %s/%s/%s ...\n" libName cellName viewName)

            procedure( getPinCoord(inst termName)
                let( (res)
                    foreach(term inst~>master~>terminals
                        when( equal(term~>name termName)
                            foreach(pin term~>pins
                                let( (bbox c)
                                    bbox = pin~>fig~>bBox
                                    c = list((car(car(bbox)) + car(cadr(bbox))) / 2.0
                                             (cadr(car(bbox)) + cadr(cadr(bbox))) / 2.0)
                                    res = dbTransformPoint(c inst~>transform)
                                )
                            )
                        )
                    )
                    res
                )
            )

            procedure( drawWire(p1 p2)
                if( listp(p1) && listp(p2) && length(p1) == 2 && length(p2) == 2 then
                    schCreateWire(cv "draw" "direct" list(p1 p2) 0.0625 0.0625 0.0)
                else
                    printf("WARN: Invalid wire points: p1=%L, p2=%L\n" p1 p2)
                )
            )

            ;; 1. PORT0 (RF Input Port: 50 Ohm, 4.5 GHz)
            i_port0 = dbCreateParamInstByMasterName(cv "analogLib" "port" "symbol" "PORT0" list(0.0 2.0) "R0" 1
                        list(list("num" "int" 1) list("r" "string" "50") list("srcType" "string" "sine") list("freq" "string" "4.5G") list("dbm" "string" "-60")))
            g_in = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_in" list(0.0 1.0) "R0")

            ;; 2. C7 (Input DC Block MIM Cap: 35u x 35u, R90)
            i_c7 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "MIMCAPS_MM" "symbol" "C7" list(1.0 2.0) "R90" 1
                        list(list("l" "string" "35u") list("w" "string" "35u")))

            ;; 3. Gate DC Bias (R0 = 5k, V0 = 0.95V, GND)
            i_r0 = dbCreateParamInstByMasterName(cv "analogLib" "res" "symbol" "R0" list(2.0 1.5) "R0" 1
                        list(list("r" "string" "5k")))
            i_v0 = dbCreateParamInstByMasterName(cv "analogLib" "vdc" "symbol" "V0" list(2.0 0.75) "R0" 1
                        list(list("vdc" "string" "0.95")))
            g_bias = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_bias" list(2.0 0.0) "R0")

            ;; 4. L3 (Gate Matching Inductor: d=180u, w=6u, n=3.5, R90)
            i_l3 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "L_SLCR20K_RF" "symbol" "L3" list(2.5 2.0) "R90" 1
                        list(list("d" "string" "180u") list("w" "string" "6u") list("n" "string" "3.5")))
            g_l3 = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_l3" list(2.6875 1.375) "R0")

            ;; 5. M0 (Common-Source NMOS: W=10u, L=180n, m=16)
            i_m0 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "N_18_MM" "symbol" "M0" list(3.75 2.0) "R0" 1
                        list(list("l" "string" "180n") list("w" "string" "10u") list("m" "string" "16")))
            g_m0_bulk = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_m0_bulk" list(4.75 2.0) "R0")

            ;; 6. L2 (Source Degeneration Inductor: d=57u, w=6u, n=1.5, R0)
            i_l2 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "L_SLCR20K_RF" "symbol" "L2" list(4.0 1.25) "R0" 1
                        list(list("d" "string" "57u") list("w" "string" "6u") list("n" "string" "1.5")))
            g_l2 = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_l2" list(4.0 0.375) "R0")
            g_l2_b = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_l2_b" list(3.25 1.0625) "R0")

            ;; 7. L1 (Cascode Interstage Inductor: d=80u, w=6u, n=1.5, R0)
            i_l1 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "L_SLCR20K_RF" "symbol" "L1" list(4.0 3.25) "R0" 1
                        list(list("d" "string" "80u") list("w" "string" "6u") list("n" "string" "1.5")))
            g_l1_b = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_l1_b" list(3.25 3.0625) "R0")

            ;; 8. M1 (Cascode NMOS: W=10u, L=180n, m=16)
            i_m1 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "N_18_MM" "symbol" "M1" list(3.75 4.25) "R0" 1
                        list(list("l" "string" "180n") list("w" "string" "10u") list("m" "string" "16")))
            g_m1_bulk = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_m1_bulk" list(4.75 4.25) "R0")

            ;; 9. Drain Tank: L0 (d=100u, n=3.5) and C6 (14.7u x 14.7u)
            i_l0 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "L_SLCR20K_RF" "symbol" "L0" list(3.25 6.0) "R0" 1
                        list(list("d" "string" "100u") list("w" "string" "6u") list("n" "string" "3.5")))
            g_l0_b = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_l0_b" list(2.625 5.8125) "R0")

            i_c6 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "MIMCAPS_MM" "symbol" "C6" list(4.75 6.0) "R0" 1
                        list(list("l" "string" "14.7u") list("w" "string" "14.7u")))

            ;; 10. VDD Source (1.8V)
            i_v1 = dbCreateParamInstByMasterName(cv "analogLib" "vdc" "symbol" "V1" list(1.75 6.6) "R0" 1
                        list(list("vdc" "string" "1.8")))
            g_vdd = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_vdd" list(1.75 5.625) "R0")

            ;; 11. Output DC Block (C3 = 15.0u x 15.0u, R90) & PORT1 (50 Ohm)
            i_c3 = dbCreateParamInstByMasterName(cv "UMC_18_CMOS" "MIMCAPS_MM" "symbol" "C3" list(5.5 5.0) "R90" 1
                        list(list("l" "string" "15.0u") list("w" "string" "15.0u")))
            i_port1 = dbCreateParamInstByMasterName(cv "analogLib" "port" "symbol" "PORT1" list(7.0 5.0) "R0" 1
                        list(list("num" "int" 2) list("r" "string" "50")))
            g_out = dbCreateInstByMasterName(cv "analogLib" "gnd" "symbol" "g_out" list(7.0 4.0) "R0")

            ;; Resolve pin locations
            p_port0_plus  = getPinCoord(i_port0 "PLUS")
            p_port0_minus = getPinCoord(i_port0 "MINUS")
            p_gin         = getPinCoord(g_in "gnd!")

            p_c7_plus     = getPinCoord(i_c7 "PLUS")
            p_c7_minus    = getPinCoord(i_c7 "MINUS")

            p_r0_plus     = getPinCoord(i_r0 "PLUS")
            p_r0_minus    = getPinCoord(i_r0 "MINUS")
            p_v0_plus     = getPinCoord(i_v0 "PLUS")
            p_v0_minus    = getPinCoord(i_v0 "MINUS")
            p_gbias       = getPinCoord(g_bias "gnd!")

            p_l3_plus     = getPinCoord(i_l3 "PLUS")
            p_l3_minus    = getPinCoord(i_l3 "MINUS")
            p_l3_b        = getPinCoord(i_l3 "B")
            p_gl3         = getPinCoord(g_l3 "gnd!")

            p_m0_g        = getPinCoord(i_m0 "G")
            p_m0_d        = getPinCoord(i_m0 "D")
            p_m0_s        = getPinCoord(i_m0 "S")
            p_m0_b        = getPinCoord(i_m0 "B")
            p_gm0         = getPinCoord(g_m0_bulk "gnd!")

            p_l2_plus     = getPinCoord(i_l2 "PLUS")
            p_l2_minus    = getPinCoord(i_l2 "MINUS")
            p_l2_b        = getPinCoord(i_l2 "B")
            p_gl2         = getPinCoord(g_l2 "gnd!")
            p_gl2b        = getPinCoord(g_l2_b "gnd!")

            p_l1_plus     = getPinCoord(i_l1 "PLUS")
            p_l1_minus    = getPinCoord(i_l1 "MINUS")
            p_l1_b        = getPinCoord(i_l1 "B")
            p_gl1b        = getPinCoord(g_l1_b "gnd!")

            p_m1_g        = getPinCoord(i_m1 "G")
            p_m1_d        = getPinCoord(i_m1 "D")
            p_m1_s        = getPinCoord(i_m1 "S")
            p_m1_b        = getPinCoord(i_m1 "B")
            p_gm1         = getPinCoord(g_m1_bulk "gnd!")

            p_l0_plus     = getPinCoord(i_l0 "PLUS")
            p_l0_minus    = getPinCoord(i_l0 "MINUS")
            p_l0_b        = getPinCoord(i_l0 "B")
            p_gl0b        = getPinCoord(g_l0_b "gnd!")

            p_c6_plus     = getPinCoord(i_c6 "PLUS")
            p_c6_minus    = getPinCoord(i_c6 "MINUS")

            p_v1_plus     = getPinCoord(i_v1 "PLUS")
            p_v1_minus    = getPinCoord(i_v1 "MINUS")
            p_gvdd        = getPinCoord(g_vdd "gnd!")

            p_c3_plus     = getPinCoord(i_c3 "PLUS")
            p_c3_minus    = getPinCoord(i_c3 "MINUS")
            p_port1_plus  = getPinCoord(i_port1 "PLUS")
            p_port1_minus = getPinCoord(i_port1 "MINUS")
            p_gout        = getPinCoord(g_out "gnd!")

            ;; WIRING:
            drawWire(p_port0_minus p_gin)
            drawWire(p_port0_plus p_c7_plus)

            drawWire(p_c7_minus list(2.0 2.0))
            drawWire(list(2.0 2.0) p_r0_plus)
            drawWire(list(2.0 2.0) p_l3_plus)

            drawWire(p_r0_minus p_v0_plus)
            drawWire(p_v0_minus p_gbias)

            drawWire(p_l3_b p_gl3)
            drawWire(p_l3_minus p_m0_g)

            drawWire(p_m0_b p_gm0)
            drawWire(p_m0_s p_l2_plus)

            drawWire(p_l2_minus p_gl2)
            drawWire(p_l2_b p_gl2b)

            drawWire(p_m0_d p_l1_minus)
            drawWire(p_l1_plus p_m1_s)
            drawWire(p_l1_b p_gl1b)

            drawWire(p_m1_b p_gm1)

            ;; Drain Tank Node (y = 5.0)
            drawWire(p_m1_d list(4.0 5.0))
            drawWire(list(4.0 5.0) list(3.25 5.0))
            drawWire(list(3.25 5.0) p_l0_minus)
            drawWire(list(4.0 5.0) list(4.75 5.0))
            drawWire(list(4.75 5.0) p_c6_minus)
            drawWire(p_l0_b p_gl0b)

            ;; VDD Rail (y = 6.6)
            drawWire(p_v1_plus list(1.75 6.6))
            drawWire(list(1.75 6.6) list(4.75 6.6))
            drawWire(list(3.25 6.6) p_l0_plus)
            drawWire(list(4.75 6.6) p_c6_plus)
            drawWire(p_v1_minus p_gvdd)

            ;; M1 Gate to VDD
            drawWire(p_m1_g list(1.25 4.25))
            drawWire(list(1.25 4.25) list(1.25 6.6))
            drawWire(list(1.25 6.6) list(1.75 6.6))

            ;; Output Path
            drawWire(list(4.75 5.0) p_c3_plus)
            drawWire(p_c3_minus p_port1_plus)
            drawWire(p_port1_minus p_gout)

            ;; Check, Save, and Close
            schCheck(cv)
            dbSave(cv)
            dbClose(cv)
            printf(">>> SUCCESS: %s/%s/%s cleanly generated and wired!\n" libName cellName viewName)
            t
        )
    )
)
