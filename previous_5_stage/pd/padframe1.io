(globals
	version = 3
	io_order = clockwise
	space = 20
	total_edge = 7
)
(iopad
	(topleft
		(inst name="CornerCell1" cell=pfrelr offset=0 orientation=R180 place_status=fixed)
	)

	(left
		(inst name="VSS"      cell=pv0i   offset=216.442  place_status=fixed)
		(inst name="GPIO23"   cell=pc3b01 offset=372.885  place_status=fixed)
		(inst name="GPIO24"   cell=pc3b01 offset=529.327  place_status=fixed)
		(inst name="GPIO25"   cell=pc3b01 offset=685.769  place_status=fixed)
		(inst name="GPIO26"   cell=pc3b01 offset=842.212  place_status=fixed)
		(inst name="GPIO27"   cell=pc3b01 offset=998.654  place_status=fixed)
		(inst name="GPIO28"   cell=pc3b01 offset=1155.096 place_status=fixed)
		(inst name="GPIO29"   cell=pc3b01 offset=1311.539 place_status=fixed)
		(inst name="GPIO30"   cell=pc3b01 offset=1467.981 place_status=fixed)
		(inst name="GPIO31"   cell=pc3b01 offset=1624.424 place_status=fixed)
		(inst name="Irst_n"   cell=pc3d01 offset=1780.866 place_status=fixed)
		(inst name="Iscan_en" cell=pc3d01 offset=1937.308 place_status=fixed)
		(inst name="Iscan_in" cell=pc3d01 offset=2093.751 place_status=fixed)
		(inst name="Oscan_out" cell=pc3o01 offset=2250.193 place_status=fixed)
		(inst name="Iclk"     cell=pc3c01 offset=2406.635 place_status=fixed)
		(inst name="VDD"      cell=pvdi   offset=2563.078 place_status=fixed)
	)

	(topright
		(inst name="CornerCell2" cell=pfrelr offset=0 orientation=R90 place_status=fixed)
	)

	(top
		(inst name="VDDO"   cell=pvda   offset=216.519  place_status=fixed)
		(inst name="GPIO22" cell=pc3b01 offset=373.037  place_status=fixed)
		(inst name="GPIO21" cell=pc3b01 offset=529.556  place_status=fixed)
		(inst name="GPIO20" cell=pc3b01 offset=686.074  place_status=fixed)
		(inst name="GPIO19" cell=pc3b01 offset=842.593  place_status=fixed)
		(inst name="GPIO18" cell=pc3b01 offset=999.111  place_status=fixed)
		(inst name="GPIO17" cell=pc3b01 offset=1155.630 place_status=fixed)
		(inst name="GPIO16" cell=pc3b01 offset=1312.148 place_status=fixed)
		(inst name="GPIO15" cell=pc3b01 offset=1468.667 place_status=fixed)
		(inst name="GPIO14" cell=pc3b01 offset=1625.185 place_status=fixed)
		(inst name="GPIO13" cell=pc3b01 offset=1781.704 place_status=fixed)
		(inst name="GPIO12" cell=pc3b01 offset=1938.222 place_status=fixed)
		(inst name="GPIO11" cell=pc3b01 offset=2094.741 place_status=fixed)
		(inst name="GPIO10" cell=pc3b01 offset=2251.259 place_status=fixed)
		(inst name="GPIO9"  cell=pc3b01 offset=2407.778 place_status=fixed)
		(inst name="VSSO"   cell=pv0a   offset=2564.296 place_status=fixed)
	)

	(bottomright
		(inst name="CornerCell3" cell=pfrelr offset=0 orientation=R0 place_status=fixed)
	)

	(right
		(inst name="VDD2"    cell=pvdi   offset=216.442  place_status=fixed)
		(inst name="SPI_SCK" cell=pc3b01 offset=372.885  place_status=fixed)
		(inst name="I2C_SDA" cell=pc3b01 offset=529.327  place_status=fixed)
		(inst name="I2C_SCL" cell=pc3b01 offset=685.769  place_status=fixed)
		(inst name="Iuart_rx" cell=pc3d01 offset=842.212 place_status=fixed)
		(inst name="Ouart_tx" cell=pc3o01 offset=998.654 place_status=fixed)
		(inst name="GPIO0"   cell=pc3b01 offset=1155.096 place_status=fixed)
		(inst name="GPIO1"   cell=pc3b01 offset=1311.539 place_status=fixed)
		(inst name="GPIO2"   cell=pc3b01 offset=1467.981 place_status=fixed)
		(inst name="GPIO3"   cell=pc3b01 offset=1624.424 place_status=fixed)
		(inst name="GPIO4"   cell=pc3b01 offset=1780.866 place_status=fixed)
		(inst name="GPIO5"   cell=pc3b01 offset=1937.308 place_status=fixed)
		(inst name="GPIO6"   cell=pc3b01 offset=2093.751 place_status=fixed)
		(inst name="GPIO7"   cell=pc3b01 offset=2250.193 place_status=fixed)
		(inst name="GPIO8"   cell=pc3b01 offset=2406.635 place_status=fixed)
		(inst name="VSS2"    cell=pv0i   offset=2563.078 place_status=fixed)
	)

	(bottomleft
		(inst name="CornerCell4" cell=pfrelr offset=0 orientation=R270 place_status=fixed)
	)

	(bottom
		(inst name="VSSO2"    cell=pv0a   offset=216.519  place_status=fixed)
		(inst name="SPI_MOSI" cell=pc3b01 offset=373.037  place_status=fixed)
		(inst name="SPI_MISO" cell=pc3b01 offset=529.556  place_status=fixed)
		(inst name="SPI_CS"   cell=pc3b01 offset=686.074  place_status=fixed)
		(inst name="OPCSrcE1" cell=pc3o01 offset=842.593  place_status=fixed)
		(inst name="dummy2"   cell=pc3d01 offset=999.111  place_status=fixed)
		(inst name="dummy3"   cell=pc3d01 offset=1155.630 place_status=fixed)
		(inst name="dummy4"   cell=pc3d01 offset=1312.148 place_status=fixed)
		(inst name="dummy5"   cell=pc3d01 offset=1468.667 place_status=fixed)
		(inst name="dummy6"   cell=pc3d01 offset=1625.185 place_status=fixed)
		(inst name="dummy7"   cell=pc3d01 offset=1781.704 place_status=fixed)
		(inst name="dummy8"   cell=pc3d01 offset=1938.222 place_status=fixed)
		(inst name="dummy9"   cell=pc3d01 offset=2094.741 place_status=fixed)
		(inst name="dummy10"  cell=pc3d01 offset=2251.259 place_status=fixed)
		(inst name="dummy11"  cell=pc3d01 offset=2407.778 place_status=fixed)
		(inst name="VDDO2"    cell=pvda   offset=2564.296 place_status=fixed)
	)
)
(globals
	version = 3
	io_order = clockwise
	space = 20
	total_edge = 7
)
(iopad
	(topleft
		(inst name="CornerCell1" cell=pfrelr offset=0 orientation=R180 place_status=fixed)
	)

	(left
		(inst name="VSS"      cell=pv0i   offset=216.442  place_status=fixed)
		(inst name="GPIO23"   cell=pc3b01 offset=372.885  place_status=fixed)
		(inst name="GPIO24"   cell=pc3b01 offset=529.327  place_status=fixed)
		(inst name="GPIO25"   cell=pc3b01 offset=685.769  place_status=fixed)
		(inst name="GPIO26"   cell=pc3b01 offset=842.212  place_status=fixed)
		(inst name="GPIO27"   cell=pc3b01 offset=998.654  place_status=fixed)
		(inst name="GPIO28"   cell=pc3b01 offset=1155.096 place_status=fixed)
		(inst name="GPIO29"   cell=pc3b01 offset=1311.539 place_status=fixed)
		(inst name="GPIO30"   cell=pc3b01 offset=1467.981 place_status=fixed)
		(inst name="GPIO31"   cell=pc3b01 offset=1624.424 place_status=fixed)
		(inst name="Irst_n"   cell=pc3d01 offset=1780.866 place_status=fixed)
		(inst name="Iscan_en" cell=pc3d01 offset=1937.308 place_status=fixed)
		(inst name="Iscan_in" cell=pc3d01 offset=2093.751 place_status=fixed)
		(inst name="Oscan_out" cell=pc3o01 offset=2250.193 place_status=fixed)
		(inst name="Iclk"     cell=pc3c01 offset=2406.635 place_status=fixed)
		(inst name="VDD"      cell=pvdi   offset=2563.078 place_status=fixed)
	)

	(topright
		(inst name="CornerCell2" cell=pfrelr offset=0 orientation=R90 place_status=fixed)
	)

	(top
		(inst name="VDDO"   cell=pvda   offset=216.519  place_status=fixed)
		(inst name="GPIO22" cell=pc3b01 offset=373.037  place_status=fixed)
		(inst name="GPIO21" cell=pc3b01 offset=529.556  place_status=fixed)
		(inst name="GPIO20" cell=pc3b01 offset=686.074  place_status=fixed)
		(inst name="GPIO19" cell=pc3b01 offset=842.593  place_status=fixed)
		(inst name="GPIO18" cell=pc3b01 offset=999.111  place_status=fixed)
		(inst name="GPIO17" cell=pc3b01 offset=1155.630 place_status=fixed)
		(inst name="GPIO16" cell=pc3b01 offset=1312.148 place_status=fixed)
		(inst name="GPIO15" cell=pc3b01 offset=1468.667 place_status=fixed)
		(inst name="GPIO14" cell=pc3b01 offset=1625.185 place_status=fixed)
		(inst name="GPIO13" cell=pc3b01 offset=1781.704 place_status=fixed)
		(inst name="GPIO12" cell=pc3b01 offset=1938.222 place_status=fixed)
		(inst name="GPIO11" cell=pc3b01 offset=2094.741 place_status=fixed)
		(inst name="GPIO10" cell=pc3b01 offset=2251.259 place_status=fixed)
		(inst name="GPIO9"  cell=pc3b01 offset=2407.778 place_status=fixed)
		(inst name="VSSO"   cell=pv0a   offset=2564.296 place_status=fixed)
	)

	(bottomright
		(inst name="CornerCell3" cell=pfrelr offset=0 orientation=R0 place_status=fixed)
	)

	(right
		(inst name="VDD2"    cell=pvdi   offset=216.442  place_status=fixed)
		(inst name="SPI_SCK" cell=pc3b01 offset=372.885  place_status=fixed)
		(inst name="I2C_SDA" cell=pc3b01 offset=529.327  place_status=fixed)
		(inst name="I2C_SCL" cell=pc3b01 offset=685.769  place_status=fixed)
		(inst name="Iuart_rx" cell=pc3d01 offset=842.212 place_status=fixed)
		(inst name="Ouart_tx" cell=pc3o01 offset=998.654 place_status=fixed)
		(inst name="GPIO0"   cell=pc3b01 offset=1155.096 place_status=fixed)
		(inst name="GPIO1"   cell=pc3b01 offset=1311.539 place_status=fixed)
		(inst name="GPIO2"   cell=pc3b01 offset=1467.981 place_status=fixed)
		(inst name="GPIO3"   cell=pc3b01 offset=1624.424 place_status=fixed)
		(inst name="GPIO4"   cell=pc3b01 offset=1780.866 place_status=fixed)
		(inst name="GPIO5"   cell=pc3b01 offset=1937.308 place_status=fixed)
		(inst name="GPIO6"   cell=pc3b01 offset=2093.751 place_status=fixed)
		(inst name="GPIO7"   cell=pc3b01 offset=2250.193 place_status=fixed)
		(inst name="GPIO8"   cell=pc3b01 offset=2406.635 place_status=fixed)
		(inst name="VSS2"    cell=pv0i   offset=2563.078 place_status=fixed)
	)

	(bottomleft
		(inst name="CornerCell4" cell=pfrelr offset=0 orientation=R270 place_status=fixed)
	)

	(bottom
		(inst name="VSSO2"    cell=pv0a   offset=216.519  place_status=fixed)
		(inst name="SPI_MOSI" cell=pc3b01 offset=373.037  place_status=fixed)
		(inst name="SPI_MISO" cell=pc3b01 offset=529.556  place_status=fixed)
		(inst name="SPI_CS"   cell=pc3b01 offset=686.074  place_status=fixed)
		(inst name="OPCSrcE1" cell=pc3o01 offset=842.593  place_status=fixed)
		(inst name="dummy2"   cell=pc3d01 offset=999.111  place_status=fixed)
		(inst name="dummy3"   cell=pc3d01 offset=1155.630 place_status=fixed)
		(inst name="dummy4"   cell=pc3d01 offset=1312.148 place_status=fixed)
		(inst name="dummy5"   cell=pc3d01 offset=1468.667 place_status=fixed)
		(inst name="dummy6"   cell=pc3d01 offset=1625.185 place_status=fixed)
		(inst name="dummy7"   cell=pc3d01 offset=1781.704 place_status=fixed)
		(inst name="dummy8"   cell=pc3d01 offset=1938.222 place_status=fixed)
		(inst name="dummy9"   cell=pc3d01 offset=2094.741 place_status=fixed)
		(inst name="dummy10"  cell=pc3d01 offset=2251.259 place_status=fixed)
		(inst name="dummy11"  cell=pc3d01 offset=2407.778 place_status=fixed)
		(inst name="VDDO2"    cell=pvda   offset=2564.296 place_status=fixed)
	)
)

