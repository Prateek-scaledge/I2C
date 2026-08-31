//----------------------------------------------------------------------------
// The confidential and proprietary information contained in this file may
// only be used by a person authorised under and to the extent permitted
// by a subsisting licensing agreement from Scaledge Technology or its affiliates.
//
// (C) COPYRIGHT 2025-2026 Scaledge Technology or its affiliates.
// ALL RIGHTS RESERVED
//
// This entire notice must be reproduced on all copies of this file
// and copies of this file may only be made by a person if such person is
// permitted to do so under the terms of a subsisting license agreement
// from Scaledge Technology or its affiliates.
//
// Release Information : 
//
//----------------------------------------------------------------------------
// Purpose : cortexm3_soc.v 
// Description: Dual Cortex-M3 SoC.  Two CORTEXM3INTEGRATIONDS cores (i0/i1)
//   share a cm3_matrix_lite 9-master / 6-slave bus matrix.
//   CPU0 occupies SI0(ICODE), SI1(DCODE), SI2(SYSTEM).
//   CPU1 occupies SI3(ICODE), SI4(DCODE), SI5(SYSTEM).
//   SI6-SI8 are tied IDLE.
//   sram_a a0 hangs on MI0, sram_a a1 on MI1.
//   cmsdk_ahb_to_sram_S / cmsdk_fpga_sram_S remain on MI3.
//   ahb_to_apb bridge stays on MI2.
//   MI4-MI5 are stubs (HREADYOUT=1, HRESP=0, HRDATA=0).
//----------------------------------------------------------------------------

module cortexm3_soc (HCLK, HRESETn, RX_i_AU, TX_o_AU, SCL_o, SDA_o, mac_txd, mac_tx_en, mac_tx_err, mac_intr_w, mac_col, mac_crs, mac_rxd, mac_rx_dv, mac_rx_err);

  parameter SRAMA_AW = 16;
  parameter SRAMS_AW = 17;

  input  HCLK;
  input  HRESETn;
  input  RX_i_AU;
  output TX_o_AU;

	inout SCL_o;
	inout SDA_o;

  output mac_txd,mac_tx_en,mac_tx_err,mac_intr_w;
  input  mac_col,mac_crs,mac_rxd,mac_rx_dv,mac_rx_err; 

  //==========================================================================
  // Clocks / resets (implicit in original; declared explicitly here)
  //==========================================================================
  wire   PORESETn;
  wire   SYSRESETn;
  wire   FCLK;

  assign SYSRESETn = HRESETn;
  assign PORESETn  = HRESETn;
  assign FCLK      = HCLK;

  //==========================================================================
  // CPU0 (i0) – control / status signals
  // Shared control inputs (ISOLATEn … DNOTITRANS) are reused by CPU1 i1.
  //==========================================================================
  reg          ISOLATEn;
  reg          RETAINn;
  reg          nTRST;
  reg          SWDITMS;
  reg          SWCLKTCK;
  reg          TDI;
  reg          CDBGPWRUPACK;
  reg          RSTBYPASS;
  reg          CGBYPASS;
  reg          TRACECLKIN;
  reg          STCLK;
  reg  [25:0]  STCALIB;
  reg  [31:0]  AUXFAULT;
  reg          BIGEND;
  reg  [239:0] INTISR;           // bit[0] wired to UART event below
  reg          INTNMI;
  // CPU0 ICODE feedback (from matrix SI0)
  wire         HREADYI;
  wire [31:0]  HRDATAI;
  wire [1:0]   HRESPI;
  reg          IFLUSH;
  // CPU0 DCODE feedback (from matrix SI1)
  wire         HREADYD;
  wire [31:0]  HRDATAD;
  wire [1:0]   HRESPD;
  reg          EXRESPD;
  // CPU0 SYSTEM feedback (from matrix SI2)
  wire         HREADYS;
  wire [31:0]  HRDATAS;
  wire [1:0]   HRESPS;
  reg          EXRESPS;
  // Shared event / mode controls
  reg          RXEV;
  reg          SLEEPHOLDREQn;
  reg          EDBGRQ;
  reg          DBGRESTART;
  reg          FIXMASTERTYPE;
  reg          WICENREQ;
  reg  [47:0]  TSVALUEB;
  reg          SE;
  reg          MPUDISABLE;
  reg          DBGEN;
  reg          NIDEN;
  reg          DNOTITRANS;
  // CPU0 debug / trace outputs
  wire         TDO;
  wire         nTDOEN;
  wire         CDBGPWRUPREQ;
  wire         SWDO;
  wire         SWDOEN;
  wire         JTAGNSW;
  wire         SWV;
  wire         TRACECLK;
  wire [3:0]   TRACEDATA;
  wire [31:0]  HTMDHADDR;
  wire [1:0]   HTMDHTRANS;
  wire [2:0]   HTMDHSIZE;
  wire [2:0]   HTMDHBURST;
  wire [3:0]   HTMDHPROT;
  wire [31:0]  HTMDHWDATA;
  wire         HTMDHWRITE;
  wire [31:0]  HTMDHRDATA;
  wire         HTMDHREADY;
  wire [1:0]   HTMDHRDATA_resp; // placeholder – tied to 0 for i0 HTM port
  // CPU0 ICODE outputs (→ SI0)
  wire [1:0]   HTRANSI;
  wire [2:0]   HSIZEI;
  wire [31:0]  HADDRI;
  wire [2:0]   HBURSTI;
  wire [3:0]   HPROTI;
  wire [1:0]   MEMATTRI;
  // CPU0 DCODE outputs (→ SI1)
  wire [1:0]   HMASTERD;
  wire [1:0]   HTRANSD;
  wire [2:0]   HSIZED;
  wire [31:0]  HADDRD;
  wire [2:0]   HBURSTD;
  wire [3:0]   HPROTD;
  wire [1:0]   MEMATTRD;
  wire         EXREQD;
  wire         HWRITED;
  wire [31:0]  HWDATAD;
  // CPU0 SYSTEM outputs (→ SI3)
  wire [1:0]   HMASTERS;
  wire [1:0]   HTRANSS;
  wire         HWRITES;
  wire [2:0]   HSIZES;
  wire         HMASTLOCKS;
  wire [31:0]  HADDRS;
  wire [31:0]  HWDATAS;
  wire [2:0]   HBURSTS;
  wire [3:0]   HPROTS;
  wire [1:0]   MEMATTRS;
  wire         EXREQS;
  // CPU0 status outputs
  wire [3:0]   BRCHSTAT;
  wire         HALTED;
  wire         DBGRESTARTED;
  wire         LOCKUP;
  wire         SLEEPING;
  wire         SLEEPDEEP;
  wire         SLEEPHOLDACKn;
  wire [8:0]   ETMINTNUM;
  wire [2:0]   ETMINTSTAT;
  wire         TRCENA;
  wire [7:0]   CURRPRI;
  wire         SYSRESETREQ;
  wire         TXEV;
  wire         GATEHCLK;
  wire         WICENACK;
  wire         WAKEUP;

  //==========================================================================
  // CPU1 (i1) – independent AHB bus signals
  //==========================================================================
  // CPU1 ICODE outputs (→ SI3)
  wire [1:0]   HTRANSI_i1;
  wire [2:0]   HSIZEI_i1;
  wire [31:0]  HADDRI_i1;
  wire [2:0]   HBURSTI_i1;
  wire [3:0]   HPROTI_i1;
  wire [1:0]   MEMATTRI_i1;
  // CPU1 DCODE outputs (→ SI4)
  wire [1:0]   HMASTERD_i1;
  wire [1:0]   HTRANSD_i1;
  wire [2:0]   HSIZED_i1;
  wire [31:0]  HADDRD_i1;
  wire [2:0]   HBURSTD_i1;
  wire [3:0]   HPROTD_i1;
  wire [1:0]   MEMATTRD_i1;
  wire         EXREQD_i1;
  wire         HWRITED_i1;
  wire [31:0]  HWDATAD_i1;
  // CPU1 SYSTEM outputs (→ SI5)
  wire [1:0]   HMASTERS_i1;
  wire [1:0]   HTRANSS_i1;
  wire         HWRITES_i1;
  wire [2:0]   HSIZES_i1;
  wire         HMASTLOCKS_i1;
  wire [31:0]  HADDRS_i1;
  wire [31:0]  HWDATAS_i1;
  wire [2:0]   HBURSTS_i1;
  wire [3:0]   HPROTS_i1;
  wire [1:0]   MEMATTRS_i1;
  wire         EXREQS_i1;
  // CPU1 per-port controls (independent)
  reg          IFLUSH_i1;
  reg          EXRESPD_i1;
  reg          EXRESPS_i1;
  // CPU1 debug / trace outputs (not connected to top-level pins)
  wire         TDO_i1;
  wire         nTDOEN_i1;
  wire         CDBGPWRUPREQ_i1;
  wire         SWDO_i1;
  wire         SWDOEN_i1;
  wire         JTAGNSW_i1;
  wire         SWV_i1;
  wire         TRACECLK_i1;
  wire [3:0]   TRACEDATA_i1;
  wire [31:0]  HTMDHADDR_i1;
  wire [1:0]   HTMDHTRANS_i1;
  wire [2:0]   HTMDHSIZE_i1;
  wire [2:0]   HTMDHBURST_i1;
  wire [3:0]   HTMDHPROT_i1;
  wire [31:0]  HTMDHWDATA_i1;
  wire         HTMDHWRITE_i1;
  // CPU1 status outputs (not connected to top-level pins)
  wire [3:0]   BRCHSTAT_i1;
  wire         HALTED_i1;
  wire         DBGRESTARTED_i1;
  wire         LOCKUP_i1;
  wire         SLEEPING_i1;
  wire         SLEEPDEEP_i1;
  wire         SLEEPHOLDACKn_i1;
  wire [8:0]   ETMINTNUM_i1;
  wire [2:0]   ETMINTSTAT_i1;
  wire         TRCENA_i1;
  wire [7:0]   CURRPRI_i1;
  wire         SYSRESETREQ_i1;
  wire         TXEV_i1;
  wire         GATEHCLK_i1;
  wire         WICENACK_i1;
  wire         WAKEUP_i1;

  //==========================================================================
  // cm3_matrix_lite – slave-port (SI) input/output signals
  //==========================================================================
  reg  [3:0]   REMAP;

  // --- SI0 : CPU0 ICODE ---
  wire [31:0]  HADDRS0;
  wire [1:0]   HTRANSS0;
  wire         HWRITES0;
  wire [2:0]   HSIZES0;
  wire [2:0]   HBURSTS0;
  wire [3:0]   HPROTS0;
  wire [31:0]  HWDATAS0;
  wire         HMASTLOCKS0;
  wire [31:0]  HAUSERS0;
  wire [31:0]  HWUSERS0;
  wire [31:0]  HRDATAS0;
  wire         HREADYS0;
  wire         HRESPS0;
  wire [31:0]  HRUSERS0;

  // --- SI1 : CPU0 DCODE ---
  wire [31:0]  HADDRS1;
  wire [1:0]   HTRANSS1;
  wire         HWRITES1;
  wire [2:0]   HSIZES1;
  wire [2:0]   HBURSTS1;
  wire [3:0]   HPROTS1;
  wire [31:0]  HWDATAS1;
  wire         HMASTLOCKS1;
  wire [31:0]  HAUSERS1;
  wire [31:0]  HWUSERS1;
  wire [31:0]  HRDATAS1;
  wire         HREADYS1;
  wire         HRESPS1;
  wire [31:0]  HRUSERS1;

  // --- SI2 : CPU1 ICODE ---
  wire [31:0]  HADDRS2;
  wire [1:0]   HTRANSS2;
  wire         HWRITES2;
  wire [2:0]   HSIZES2;
  wire [2:0]   HBURSTS2;
  wire [3:0]   HPROTS2;
  wire [31:0]  HWDATAS2;
  wire         HMASTLOCKS2;
  wire [31:0]  HAUSERS2;
  wire [31:0]  HWUSERS2;
  wire [31:0]  HRDATAS2;
  wire         HREADYS2;
  wire         HRESPS2;
  wire [31:0]  HRUSERS2;

  // --- SI3 : CPU0 SYSTEM
  wire [31:0]  HADDRS3;
  wire [1:0]   HTRANSS3;
  wire         HWRITES3;
  wire [2:0]   HSIZES3;
  wire [2:0]   HBURSTS3;
  wire [3:0]   HPROTS3;
  wire [31:0]  HWDATAS3;
  wire         HMASTLOCKS3;
  wire [31:0]  HAUSERS3;
  wire [31:0]  HWUSERS3;
  wire [31:0]  HRDATAS3;
  wire         HREADYS3;
  wire         HRESPS3;
  wire [31:0]  HRUSERS3;

  // --- SI4 : CPU1 DCODE (changed from reg to wire) ---
  wire [31:0]  HADDRS4;
  wire [1:0]   HTRANSS4;
  wire         HWRITES4;
  wire [2:0]   HSIZES4;
  wire [2:0]   HBURSTS4;
  wire [3:0]   HPROTS4;
  wire [31:0]  HWDATAS4;
  wire         HMASTLOCKS4;
  wire [31:0]  HAUSERS4;
  wire [31:0]  HWUSERS4;
  wire [31:0]  HRDATAS4;
  wire         HREADYS4;
  wire         HRESPS4;
  wire [31:0]  HRUSERS4;

  // --- SI5 : CPU1 SYSTEM (changed from reg to wire) ---
  wire [31:0]  HADDRS5;
  wire [1:0]   HTRANSS5;
  wire         HWRITES5;
  wire [2:0]   HSIZES5;
  wire [2:0]   HBURSTS5;
  wire [3:0]   HPROTS5;
  wire [31:0]  HWDATAS5;
  wire         HMASTLOCKS5;
  wire [31:0]  HAUSERS5;
  wire [31:0]  HWUSERS5;
  wire [31:0]  HRDATAS5;
  wire         HREADYS5;
  wire         HRESPS5;
  wire [31:0]  HRUSERS5;

  // --- SI6 : DMA read bus (driven by dma_ahb32 RH* outputs) ---
  wire [31:0]  HADDRS6;
  wire [1:0]   HTRANSS6;
  wire         HWRITES6;
  wire [2:0]   HSIZES6;
  wire [2:0]   HBURSTS6;
  wire [3:0]   HPROTS6;
  wire [31:0]  HWDATAS6;
  wire         HMASTLOCKS6;
  wire [31:0]  HAUSERS6;
  wire [31:0]  HWUSERS6;
  wire [31:0]  HRDATAS6;
  wire         HREADYS6;
  wire         HRESPS6;
  wire [31:0]  HRUSERS6;

  // --- SI7 : DMA write bus (driven by dma_ahb32 WH* outputs) ---
  wire [31:0]  HADDRS7;
  wire [1:0]   HTRANSS7;
  wire         HWRITES7;
  wire [2:0]   HSIZES7;
  wire [2:0]   HBURSTS7;
  wire [3:0]   HPROTS7;
  wire [31:0]  HWDATAS7;
  wire         HMASTLOCKS7;
  wire [31:0]  HAUSERS7;
  wire [31:0]  HWUSERS7;
  wire [31:0]  HRDATAS7;
  wire         HREADYS7;
  wire         HRESPS7;
  wire [31:0]  HRUSERS7;

  // --- SI8 : wb to ahb bridge ---

  wire [31:0]  HADDRS8    ;
  wire [1:0]   HTRANSS8   ;
  wire         HWRITES8   ;
  wire [2:0]   HSIZES8    ;
  wire [2:0]   HBURSTS8   = 3'h0;
  wire [3:0]   HPROTS8    = 4'h0;
  wire [31:0]  HWDATAS8   ;
  wire         HMASTLOCKS8 = 1'b0;
  wire [31:0]  HAUSERS8   = 32'h0;
  wire [31:0]  HWUSERS8   = 32'h0;
  wire [31:0]  HRDATAS8;
  wire         HREADYS8;
  wire         HRESPS8;
  wire [31:0]  HRUSERS8;

  //==========================================================================
  // cm3_matrix_lite – master-port (MI) signals
  //==========================================================================

  // --- MI0 : sram_a a0 ---
  wire [31:0]  HRDATAM0;        // slave→matrix: driven by a0
  wire         HREADYOUTM0;     // slave→matrix: driven by a0
  wire         HRESPM0;         // slave→matrix: driven by a0
  reg  [31:0]  HRUSERM0;        // no RUSER from SRAM; tied 0 in initial
  wire         HSELM0;
  wire [31:0]  HADDRM0;
  wire [1:0]   HTRANSM0;
  wire         HWRITEM0;
  wire [2:0]   HSIZEM0;
  wire [2:0]   HBURSTM0;
  wire [3:0]   HPROTM0;
  wire [31:0]  HWDATAM0;
  wire         HMASTLOCKM0;
  wire         HREADYMUXM0;
  wire [31:0]  HAUSERM0;
  wire [31:0]  HWUSERM0;

  // --- MI1 : sram_a a1 ---
  wire [31:0]  HRDATAM1;        // slave→matrix: driven by a1 (was reg)
  wire         HREADYOUTM1;     // slave→matrix: driven by a1 (was reg)
  wire         HRESPM1;         // slave→matrix: driven by a1 (was reg)
  reg  [31:0]  HRUSERM1;        // no RUSER from SRAM; tied 0 in initial
  wire         HSELM1;
  wire [31:0]  HADDRM1;
  wire [1:0]   HTRANSM1;
  wire         HWRITEM1;
  wire [2:0]   HSIZEM1;
  wire [2:0]   HBURSTM1;
  wire [3:0]   HPROTM1;
  wire [31:0]  HWDATAM1;
  wire         HMASTLOCKM1;
  wire         HREADYMUXM1;
  wire [31:0]  HAUSERM1;
  wire [31:0]  HWUSERM1;

  // --- MI2 : APB bridge ---
  wire [31:0]  HRDATAM2;        // driven by assign below (was reg)
  wire         HREADYOUTM2;     // driven by assign below (was reg)
  wire         HRESPM2;         // driven by assign below (was reg)
  reg  [31:0]  HRUSERM2;        // tied 0
  wire         HSELM2;
  wire [31:0]  HADDRM2;
  wire [1:0]   HTRANSM2;
  wire         HWRITEM2;
  wire [2:0]   HSIZEM2;
  wire [2:0]   HBURSTM2;
  wire [3:0]   HPROTM2;
  wire [31:0]  HWDATAM2;
  wire         HMASTLOCKM2;
  wire         HREADYMUXM2;
  wire [31:0]  HAUSERM2;
  wire [31:0]  HWUSERM2;

  // --- MI3 : System SRAM (SRAMS) ---
  wire [31:0]  HRDATAM3;
  wire         HREADYOUTM3;
  wire         HRESPM3;
  reg  [31:0]  HRUSERM3;        // tied 0
  wire         HSELM3;
  wire [31:0]  HADDRM3;
  wire [1:0]   HTRANSM3;
  wire         HWRITEM3;
  wire [2:0]   HSIZEM3;
  wire [2:0]   HBURSTM3;
  wire [3:0]   HPROTM3;
  wire [31:0]  HWDATAM3;
  wire         HMASTLOCKM3;
  wire         HREADYMUXM3;
  wire [31:0]  HAUSERM3;
  wire [31:0]  HWUSERM3;

  // --- MI4 : Wishbone memory ---
  wire [31:0]  HRDATAM4;
  wire         HREADYOUTM4;
  wire         HRESPM4;
  wire [31:0]  HRUSERM4;
  wire         HSELM4;
  wire [31:0]  HADDRM4;
  wire [1:0]   HTRANSM4;
  wire         HWRITEM4;
  wire [2:0]   HSIZEM4;
  wire [2:0]   HBURSTM4;
  wire [3:0]   HPROTM4;
  wire [31:0]  HWDATAM4;
  wire         HMASTLOCKM4;
  wire         HREADYMUXM4;
  wire [31:0]  HAUSERM4;
  wire [31:0]  HWUSERM4;

  // --- MI5 : MAC IP ---
  wire [31:0]  HRDATAM5;
  wire         HREADYOUTM5;
  wire         HRESPM5;
  wire [31:0]  HRUSERM5;
  wire         HSELM5;
  wire [31:0]  HADDRM5;
  wire [1:0]   HTRANSM5;
  wire         HWRITEM5;
  wire [2:0]   HSIZEM5;
  wire [2:0]   HBURSTM5;
  wire [3:0]   HPROTM5;
  wire [31:0]  HWDATAM5;
  wire         HMASTLOCKM5;
  wire         HREADYMUXM5;
  wire [31:0]  HAUSERM5;
  wire [31:0]  HWUSERM5;

  // Scan passthrough
  reg          SCANENABLE;
  reg          SCANINHCLK;
  wire         SCANOUTHCLK;

  //==========================================================================
  // System SRAM (SRAMS) – MI3 bridge signals
  //==========================================================================
  wire              HCLK_SRAMS;
  wire              HRESETn_SRAMS;
  wire              HSEL_SRAMS;
  wire              HREADY_SRAMS;
  wire [1:0]        HTRANS_SRAMS;
  wire [2:0]        HSIZE_SRAMS;
  wire              HWRITE_SRAMS;
  wire [SRAMS_AW-1:0] HADDR_SRAMS;
  wire [31:0]       HWDATA_SRAMS;
  wire [31:0]       SRAMRDATA_SRAMS;
  wire              HREADYOUT_SRAMS;
  wire              HRESP_SRAMS;
  wire [31:0]       HRDATA_SRAMS;
  wire [SRAMS_AW-3:0] SRAMADDR_SRAMS;
  wire [3:0]        SRAMWEN_SRAMS;
  wire [31:0]       SRAMWDATA_SRAMS;
  wire              SRAMCS_SRAMS;
  wire              CLK_SRAMS;
  wire [SRAMS_AW-1:0] ADDR_SRAMS;
  wire [31:0]       WDATA_SRAMS;
  wire [3:0]        WREN_SRAMS;
  wire              CS_SRAMS;
  wire [31:0]       RDATA_SRAMS;

  //==========================================================================
  // SRAM A0 (cmsdk_fpga_sram + cmsdk_ahb_to_sram) – MI0 bridge signals
  //==========================================================================
  wire              HCLK_SRAMA0;
  wire              HRESETn_SRAMA0;
  wire              HSEL_SRAMA0;
  wire              HREADY_SRAMA0;
  wire [1:0]        HTRANS_SRAMA0;
  wire [2:0]        HSIZE_SRAMA0;
  wire              HWRITE_SRAMA0;
  wire [SRAMA_AW-1:0] HADDR_SRAMA0;
  wire [31:0]       HWDATA_SRAMA0;
  wire [31:0]       SRAMRDATA_SRAMA0;
  wire              HREADYOUT_SRAMA0;
  wire              HRESP_SRAMA0;
  wire [31:0]       HRDATA_SRAMA0;
  wire [SRAMA_AW-3:0] SRAMADDR_SRAMA0;
  wire [3:0]        SRAMWEN_SRAMA0;
  wire [31:0]       SRAMWDATA_SRAMA0;
  wire              SRAMCS_SRAMA0;
  wire              CLK_SRAMA0;
  wire [SRAMA_AW-1:0] ADDR_SRAMA0;
  wire [31:0]       WDATA_SRAMA0;
  wire [3:0]        WREN_SRAMA0;
  wire              CS_SRAMA0;
  wire [31:0]       RDATA_SRAMA0;

  //==========================================================================
  // SRAM A1 (cmsdk_fpga_sram + cmsdk_ahb_to_sram) – MI1 bridge signals
  //==========================================================================
  wire              HCLK_SRAMA1;
  wire              HRESETn_SRAMA1;
  wire              HSEL_SRAMA1;
  wire              HREADY_SRAMA1;
  wire [1:0]        HTRANS_SRAMA1;
  wire [2:0]        HSIZE_SRAMA1;
  wire              HWRITE_SRAMA1;
  wire [SRAMA_AW-1:0] HADDR_SRAMA1;
  wire [31:0]       HWDATA_SRAMA1;
  wire [31:0]       SRAMRDATA_SRAMA1;
  wire              HREADYOUT_SRAMA1;
  wire              HRESP_SRAMA1;
  wire [31:0]       HRDATA_SRAMA1;
  wire [SRAMA_AW-3:0] SRAMADDR_SRAMA1;
  wire [3:0]        SRAMWEN_SRAMA1;
  wire [31:0]       SRAMWDATA_SRAMA1;
  wire              SRAMCS_SRAMA1;
  wire              CLK_SRAMA1;
  wire [SRAMA_AW-1:0] ADDR_SRAMA1;
  wire [31:0]       WDATA_SRAMA1;
  wire [3:0]        WREN_SRAMA1;
  wire              CS_SRAMA1;
  wire [31:0]       RDATA_SRAMA1;

  //==========================================================================
  // APB bridge signals (MI2)
  //==========================================================================
  wire        Hclk_b, Hrst_b, Hsel_b;
  wire        Hwrite_b, Hreadyout_b, Hreadyin_b;
  wire [31:0] Haddr_b;
  wire [31:0] Hwdata_b, Hrdata_b;
  wire [1:0]  Htrans_b;
  wire [2:0]  Hsize_b;
  wire [3:0]  Hprot_b;
  wire        Hresp_b;
  wire        Psel_b;
  wire        Penable_b, Pwrite_b, Pready_b;
  wire [3:0]  Pstrb_b;
  wire [31:0] Paddr_b;
  wire [31:0] Pwdata_b, Prdata_b;
  wire [2:0]  Pprot_b;
  wire        APBACTIVE_b;
  wire        Pslverr_b; 



  //==========================================================================
  // ahb to wb bridge signals (MI4)
  //==========================================================================
  wire        Hclk_ahb2wb, Hrst_ahb2wb;
  wire        Hwrite_ahb2wb, Hreadyin_ahb2wb;
  wire [31:0] Hwdata_ahb2wb, Haddr_ahb2wb; 
  wire [1:0]  Htrans_ahb2wb;
  wire [2:0]  Hsize_ahb2wb;
  wire        Hreadyout_ahb2wb;
  wire [1:0]  Hresp_ahb2wb;
  wire [31:0] Hrdata_ahb2wb;

  wire        cyc_o_ahb2wb,stb_o_ahb2wb,we_o_ahb2wb,ack_i_ahb2wb,err_i_ahb2wb;      
  wire [31:0] adr_o_ahb2wb,dat_o_ahb2wb,dat_i_ahb2wb;     
  wire [3:0]  sel_o_ahb2wb; 

  //==========================================================================
  // ahb to wb bridge signals (MI5)
  //==========================================================================
  wire        mac_Hclk_ahb2wb, mac_Hrst_ahb2wb;
  wire        mac_Hwrite_ahb2wb, mac_Hreadyin_ahb2wb;
  wire [31:0] mac_Hwdata_ahb2wb, mac_Haddr_ahb2wb; 
  wire [1:0]  mac_Htrans_ahb2wb;
  wire [2:0]  mac_Hsize_ahb2wb;
  wire        mac_Hreadyout_ahb2wb;
  wire [1:0]  mac_Hresp_ahb2wb;
  wire [31:0] mac_Hrdata_ahb2wb;

  wire        mac_cyc_o_ahb2wb,mac_stb_o_ahb2wb,mac_we_o_ahb2wb,mac_ack_i_ahb2wb,mac_err_i_ahb2wb;      
  wire [31:0] mac_adr_o_ahb2wb,mac_dat_o_ahb2wb,mac_dat_i_ahb2wb;     
  wire [3:0]  mac_sel_o_ahb2wb;

  //==========================================================================
  // wb to ahb bridge signals
  //==========================================================================
  wire        mac_Hclk_wb2ahb, mac_Hrst_wb2ahb;
  wire        mac_Hwrite_wb2ahb, mac_Hreadyin_wb2ahb;
  wire [31:0] mac_Hwdata_wb2ahb, mac_Haddr_wb2ahb; 
  wire [1:0]  mac_Htrans_wb2ahb;
  wire [2:0]  mac_Hsize_wb2ahb;
  wire        mac_Hreadyout_wb2ahb;
  wire [1:0]  mac_Hresp_wb2ahb;
  wire [31:0] mac_Hrdata_wb2ahb;

  wire        mac_cyc_i_wb2ahb,mac_stb_i_wb2ahb,mac_we_i_wb2ahb,mac_ack_o_wb2ahb,mac_err_o_wb2ahb;      
  wire [31:0] mac_adr_i_wb2ahb,mac_dat_o_wb2ahb,mac_dat_i_wb2ahb;     
  wire [3:0]  mac_sel_i_wb2ahb;


  //==========================================================================
  // mac signals
  //==========================================================================
  reg mac_tx_clk,mac_rx_clk,mac_col,mac_crs,mac_tx_en,mac_tx_err,mac_rx_dv,mac_rx_err,mac_intr_w;
  reg [3:0] mac_txd,mac_rxd;


  //==========================================================================
  // DMA APB signals
  //==========================================================================
  wire [31:0] PRDATA_DMA;    // DMA APB read-data → Prdata_b mux
  wire        PREADY_DMA;    // DMA APB ready    → pready_b mux
  wire        PSLVERR_DMA;   // DMA APB error
  wire        DMA_IDLE;      // DMA idle status output (connect as needed)
  wire        dma_int_w;     // DMA interrupt → INTISR[1]

  wire        PSEL_DMA;
  wire [31:0] PADDR_DMA;
  wire [31:0] PWDATA_DMA;
  wire        PWRITE_DMA;
  wire        PENABLE_DMA;

  //==========================================================================
  // UART APB signals
  //==========================================================================
  wire        PCLKU;
  wire        PRSTU;
  wire [31:0] PADDRU;
  wire [31:0] PWDATAU;
  wire        PWRITEU;
  wire        PSELU;
  wire        PENABLEU;
  wire [31:0] PRDATAU;
  wire        PSLVERRU;
  wire        PREADYU;
  wire [3:0]  PSTRBU;
  wire        uart_int_w;

  //==========================================================================
  // I2C APB signals
  //==========================================================================
  wire        PCLK_I2C;
  wire        PRESETn_I2C;
  wire [31:0] PADDR_I2C;
  wire [31:0] PWDATA_I2C;
  wire        PWRITE_I2C;
  wire        PSEL_I2C;
  wire        PENABLE_I2C;
  wire        PREADY_I2C;
  wire [31:0] PRDATA_I2C;
  wire        PSLVERR_I2C;

  //==========================================================================
  // APB memory signals
  //==========================================================================
  wire        PCLK_M;
  wire        PRST_M;
  wire [31:0] PADDR_M;
  wire [31:0] PWDATA_M;
  wire        PWRITE_M;
  wire        PENABLE_M;
  wire        PSEL_M;
  wire [3:0]  PSTRB_M;
  wire        PREADY_M;
  wire [31:0] PRDATA_M;
  wire        PSLVERR_M;

  //==========================================================================
  // Wishbone memory signals
  //==========================================================================
  wire        WB_CLK_M;
  wire        WB_RST_M;
  wire [31:0] WB_ADR_M;
  wire [31:0] WB_DAT_M_I;
  wire [31:0] WB_DAT_M_O;
  wire [3:0]  WB_SEL_M;
  wire        WB_WE_M;
  wire        WB_CYC_M;
  wire        WB_STB_M;
  wire        WB_ACK_M;
  wire        WB_ERR_M;

  //==========================================================================
  // Initial block
  //==========================================================================
  initial begin
    ISOLATEn      = 1;
    RETAINn       = 1;
    nTRST         = 1'b1;
    SWDITMS       = 0;
    SWCLKTCK      = 0;
    TDI           = 0;
    CDBGPWRUPACK  = 0;
    RSTBYPASS     = 0;
    CGBYPASS      = 0;
    TRACECLKIN    = 0;
    STCLK         = 0;
    STCALIB       = 0;
    AUXFAULT      = 0;
    BIGEND        = 0;
    //INTISR        = 0;
    INTNMI        = 0;
    // CPU0 per-port controls
    IFLUSH        = 0;
    EXRESPD       = 0;
    EXRESPS       = 0;
    // CPU1 per-port controls
    IFLUSH_i1     = 0;
    EXRESPD_i1    = 0;
    EXRESPS_i1    = 0;
    // Shared event / mode controls
    RXEV          = 0;
    SLEEPHOLDREQn = 1;
    EDBGRQ        = 0;
    DBGRESTART    = 0;
    FIXMASTERTYPE = 0;
    WICENREQ      = 0;
    TSVALUEB      = 0;
    SE            = 0;
    MPUDISABLE    = 0;
    DBGEN         = 0;
    NIDEN         = 0;
    DNOTITRANS    = 0;
    // Bus-matrix misc
    REMAP         = 0;
    HRUSERM0      = 0;
    HRUSERM1      = 0;
    HRUSERM2      = 0;
    HRUSERM3      = 0;
    SCANENABLE    = 0;
    SCANINHCLK    = 0;

    // Setting CPU IDs
    cmsdk_fpga_sram_A0.BRAM0[`CPU_ID_REG_INDEX] = `CPU0_ID_VALUE;
    cmsdk_fpga_sram_A0.BRAM1[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
    cmsdk_fpga_sram_A0.BRAM2[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
    cmsdk_fpga_sram_A0.BRAM3[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
    
    cmsdk_fpga_sram_A1.BRAM0[`CPU_ID_REG_INDEX] = `CPU1_ID_VALUE;
    cmsdk_fpga_sram_A1.BRAM1[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
    cmsdk_fpga_sram_A1.BRAM2[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
    cmsdk_fpga_sram_A1.BRAM3[`CPU_ID_REG_INDEX] = `DEFAULT_REG_VALUE;
  end

  //==========================================================================
  // CPU0 (i0) instantiation
  //==========================================================================
  CORTEXM3INTEGRATIONDS CORTEXM3INTEGRATIONDS_i0 (
    .ISOLATEn       (ISOLATEn),
    .RETAINn        (RETAINn),
    .nTRST          (nTRST),
    .SWDITMS        (SWDITMS),
    .SWCLKTCK       (SWCLKTCK),
    .TDI            (TDI),
    .CDBGPWRUPACK   (CDBGPWRUPACK),
    .PORESETn       (PORESETn),
    .SYSRESETn      (SYSRESETn),
    .RSTBYPASS      (RSTBYPASS),
    .CGBYPASS       (CGBYPASS),
    .FCLK           (FCLK),
    .HCLK           (HCLK),
    .TRACECLKIN     (TRACECLKIN),
    .STCLK          (STCLK),
    .STCALIB        (STCALIB),
    .AUXFAULT       (AUXFAULT),
    .BIGEND         (BIGEND),
    .INTISR         (INTISR),
    .INTNMI         (INTNMI),
    // ICODE bus (SI0)
    .HREADYI        (HREADYI),
    .HRDATAI        (HRDATAI),
    .HRESPI         (HRESPI),
    .IFLUSH         (IFLUSH),
    // DCODE bus (SI1)
    .HREADYD        (HREADYD),
    .HRDATAD        (HRDATAD),
    .HRESPD         (HRESPD),
    .EXRESPD        (EXRESPD),
    // SYSTEM bus (SI2)
    .HREADYS        (HREADYS),
    .HRDATAS        (HRDATAS),
    .HRESPS         (HRESPS),
    .EXRESPS        (EXRESPS),
    // Event / mode
    .RXEV           (RXEV),
    .SLEEPHOLDREQn (SLEEPHOLDREQn),
    .EDBGRQ         (EDBGRQ),
    .DBGRESTART     (DBGRESTART),
    .FIXMASTERTYPE  (FIXMASTERTYPE),
    .WICENREQ       (WICENREQ),
    .TSVALUEB       (TSVALUEB),
    .SE             (SE),
    .MPUDISABLE     (MPUDISABLE),
    .DBGEN          (DBGEN),
    .NIDEN          (NIDEN),
    .DNOTITRANS     (DNOTITRANS),
    // Debug / trace outputs
    .TDO            (TDO),
    .nTDOEN         (nTDOEN),
    .CDBGPWRUPREQ   (CDBGPWRUPREQ),
    .SWDO           (SWDO),
    .SWDOEN         (SWDOEN),
    .JTAGNSW        (JTAGNSW),
    .SWV            (SWV),
    .TRACECLK       (TRACECLK),
    .TRACEDATA      (TRACEDATA),
    .HTMDHADDR      (HTMDHADDR),
    .HTMDHTRANS     (HTMDHTRANS),
    .HTMDHSIZE      (HTMDHSIZE),
    .HTMDHBURST     (HTMDHBURST),
    .HTMDHPROT      (HTMDHPROT),
    .HTMDHWDATA     (HTMDHWDATA),
    .HTMDHWRITE     (HTMDHWRITE),
    .HTMDHRDATA     (32'h0),    // HTM DMA port not used
    .HTMDHREADY     (1'b1),
    .HTMDHRESP      (2'b00),
    // ICODE outputs (→ SI0)
    .HTRANSI        (HTRANSI),
    .HSIZEI         (HSIZEI),
    .HADDRI         (HADDRI),
    .HBURSTI        (HBURSTI),
    .HPROTI         (HPROTI),
    .MEMATTRI       (MEMATTRI),
    // DCODE outputs (→ SI1)
    .HMASTERD       (HMASTERD),
    .HTRANSD        (HTRANSD),
    .HSIZED         (HSIZED),
    .HADDRD         (HADDRD),
    .HBURSTD        (HBURSTD),
    .HPROTD         (HPROTD),
    .MEMATTRD       (MEMATTRD),
    .EXREQD         (EXREQD),
    .HWRITED        (HWRITED),
    .HWDATAD        (HWDATAD),
    // SYSTEM outputs (→ SI2)
    .HMASTERS       (HMASTERS),
    .HTRANSS        (HTRANSS),
    .HWRITES        (HWRITES),
    .HSIZES         (HSIZES),
    .HMASTLOCKS     (HMASTLOCKS),
    .HADDRS         (HADDRS),
    .HWDATAS        (HWDATAS),
    .HBURSTS        (HBURSTS),
    .HPROTS         (HPROTS),
    .MEMATTRS       (MEMATTRS),
    .EXREQS         (EXREQS),
    // Status outputs
    .BRCHSTAT       (BRCHSTAT),
    .HALTED         (HALTED),
    .DBGRESTARTED   (DBGRESTARTED),
    .LOCKUP         (LOCKUP),
    .SLEEPING       (SLEEPING),
    .SLEEPDEEP      (SLEEPDEEP),
    .SLEEPHOLDACKn (SLEEPHOLDACKn),
    .ETMINTNUM      (ETMINTNUM),
    .ETMINTSTAT     (ETMINTSTAT),
    .TRCENA         (TRCENA),
    .CURRPRI        (CURRPRI),
    .SYSRESETREQ    (SYSRESETREQ),
    .TXEV           (TXEV),
    .GATEHCLK       (GATEHCLK),
    .WICENACK       (WICENACK),
    .WAKEUP         (WAKEUP)
  );

  //==========================================================================
  // CPU1 (i1) instantiation
  // Shared control inputs reuse CPU0 reg signals.
  // Independent AHB buses go to SI3/SI4/SI5.
  // Debug / trace outputs are unconnected at top level.
  //==========================================================================
  CORTEXM3INTEGRATIONDS CORTEXM3INTEGRATIONDS_i1 (
    // Shared control inputs
    .ISOLATEn       (ISOLATEn),
    .RETAINn        (RETAINn),
    .nTRST          (nTRST),
    .SWDITMS        (SWDITMS),
    .SWCLKTCK       (SWCLKTCK),
    .TDI            (TDI),
    .CDBGPWRUPACK   (CDBGPWRUPACK),
    .PORESETn       (PORESETn),
    .SYSRESETn      (SYSRESETn),
    .RSTBYPASS      (RSTBYPASS),
    .CGBYPASS       (CGBYPASS),
    .FCLK           (FCLK),
    .HCLK           (HCLK),
    .TRACECLKIN     (TRACECLKIN),
    .STCLK          (STCLK),
    .STCALIB        (STCALIB),
    .AUXFAULT       (AUXFAULT),
    .BIGEND         (BIGEND),
    .INTISR         (INTISR),
    .INTNMI         (INTNMI),
    // ICODE bus feedback (from matrix SI3)
    .HREADYI        (HREADYS2),
    .HRDATAI        (HRDATAS2),
    .HRESPI         (HRESPS2),
    .IFLUSH         (IFLUSH_i1),
    // DCODE bus feedback (from matrix SI4)
    .HREADYD        (HREADYS4),
    .HRDATAD        (HRDATAS4),
    .HRESPD         (HRESPS4),
    .EXRESPD        (EXRESPD_i1),
    // SYSTEM bus feedback (from matrix SI5)
    .HREADYS        (HREADYS5),
    .HRDATAS        (HRDATAS5),
    .HRESPS         (HRESPS5),
    .EXRESPS        (EXRESPS_i1),
    // Shared event / mode
    .RXEV           (RXEV),
    .SLEEPHOLDREQn (SLEEPHOLDREQn),
    .EDBGRQ         (EDBGRQ),
    .DBGRESTART     (DBGRESTART),
    .FIXMASTERTYPE  (FIXMASTERTYPE),
    .WICENREQ       (WICENREQ),
    .TSVALUEB       (TSVALUEB),
    .SE             (SE),
    .MPUDISABLE     (MPUDISABLE),
    .DBGEN          (DBGEN),
    .NIDEN          (NIDEN),
    .DNOTITRANS     (DNOTITRANS),
    // Debug / trace outputs (not connected to top-level pins)
    .TDO            (TDO_i1),
    .nTDOEN         (nTDOEN_i1),
    .CDBGPWRUPREQ   (CDBGPWRUPREQ_i1),
    .SWDO           (SWDO_i1),
    .SWDOEN         (SWDOEN_i1),
    .JTAGNSW        (JTAGNSW_i1),
    .SWV            (SWV_i1),
    .TRACECLK       (TRACECLK_i1),
    .TRACEDATA      (TRACEDATA_i1),
    .HTMDHADDR      (HTMDHADDR_i1),
    .HTMDHTRANS     (HTMDHTRANS_i1),
    .HTMDHSIZE      (HTMDHSIZE_i1),
    .HTMDHBURST     (HTMDHBURST_i1),
    .HTMDHPROT      (HTMDHPROT_i1),
    .HTMDHWDATA     (HTMDHWDATA_i1),
    .HTMDHWRITE     (HTMDHWRITE_i1),
    .HTMDHRDATA     (32'h0),    // HTM DMA port not used
    .HTMDHREADY     (1'b1),
    .HTMDHRESP      (2'b00),
    // ICODE outputs (→ SI3)
    .HTRANSI        (HTRANSI_i1),
    .HSIZEI         (HSIZEI_i1),
    .HADDRI         (HADDRI_i1),
    .HBURSTI        (HBURSTI_i1),
    .HPROTI         (HPROTI_i1),
    .MEMATTRI       (MEMATTRI_i1),
    // DCODE outputs (→ SI4)
    .HMASTERD       (HMASTERD_i1),
    .HTRANSD        (HTRANSD_i1),
    .HSIZED         (HSIZED_i1),
    .HADDRD         (HADDRD_i1),
    .HBURSTD        (HBURSTD_i1),
    .HPROTD         (HPROTD_i1),
    .MEMATTRD       (MEMATTRD_i1),
    .EXREQD         (EXREQD_i1),
    .HWRITED        (HWRITED_i1),
    .HWDATAD        (HWDATAD_i1),
    // SYSTEM outputs (→ SI5)
    .HMASTERS       (HMASTERS_i1),
    .HTRANSS        (HTRANSS_i1),
    .HWRITES        (HWRITES_i1),
    .HSIZES         (HSIZES_i1),
    .HMASTLOCKS     (HMASTLOCKS_i1),
    .HADDRS         (HADDRS_i1),
    .HWDATAS        (HWDATAS_i1),
    .HBURSTS        (HBURSTS_i1),
    .HPROTS         (HPROTS_i1),
    .MEMATTRS       (MEMATTRS_i1),
    .EXREQS         (EXREQS_i1),
    // Status outputs (not connected to top-level pins)
    .BRCHSTAT       (BRCHSTAT_i1),
    .HALTED         (HALTED_i1),
    .DBGRESTARTED   (DBGRESTARTED_i1),
    .LOCKUP         (LOCKUP_i1),
    .SLEEPING       (SLEEPING_i1),
    .SLEEPDEEP      (SLEEPDEEP_i1),
    .SLEEPHOLDACKn (SLEEPHOLDACKn_i1),
    .ETMINTNUM      (ETMINTNUM_i1),
    .ETMINTSTAT     (ETMINTSTAT_i1),
    .TRCENA         (TRCENA_i1),
    .CURRPRI        (CURRPRI_i1),
    .SYSRESETREQ    (SYSRESETREQ_i1),
    .TXEV           (TXEV_i1),
    .GATEHCLK       (GATEHCLK_i1),
    .WICENACK       (WICENACK_i1),
    .WAKEUP         (WAKEUP_i1)
  );

  //==========================================================================
  // Bus matrix
  //==========================================================================
  cm3_matrix_lite cm3_matrix_lite (
    .HCLK             (HCLK),
    .HRESETn          (HRESETn),
    .REMAP            (REMAP),
    // SI0 – CPU0 ICODE
    .HADDRS0          (HADDRS0),
    .HTRANSS0         (HTRANSS0),
    .HWRITES0         (HWRITES0),
    .HSIZES0          (HSIZES0),
    .HBURSTS0         (HBURSTS0),
    .HPROTS0          (HPROTS0),
    .HWDATAS0         (HWDATAS0),
    .HMASTLOCKS0      (HMASTLOCKS0),
    .HAUSERS0         (HAUSERS0),
    .HWUSERS0         (HWUSERS0),
    // SI1 – CPU0 DCODE
    .HADDRS1          (HADDRS1),
    .HTRANSS1         (HTRANSS1),
    .HWRITES1         (HWRITES1),
    .HSIZES1          (HSIZES1),
    .HBURSTS1         (HBURSTS1),
    .HPROTS1          (HPROTS1),
    .HWDATAS1         (HWDATAS1),
    .HMASTLOCKS1      (HMASTLOCKS1),
    .HAUSERS1         (HAUSERS1),
    .HWUSERS1         (HWUSERS1),
    // SI3 – CPU1 ICODE
    .HADDRS2          (HADDRS2),
    .HTRANSS2         (HTRANSS2),
    .HWRITES2         (HWRITES2),
    .HSIZES2          (HSIZES2),
    .HBURSTS2         (HBURSTS2),
    .HPROTS2          (HPROTS2),
    .HWDATAS2         (HWDATAS2),
    .HMASTLOCKS2      (HMASTLOCKS2),
    .HAUSERS2         (HAUSERS2),
    .HWUSERS2         (HWUSERS2),
    // SI2 – CPU0 SYSTEM
    .HADDRS3          (HADDRS3),
    .HTRANSS3         (HTRANSS3),
    .HWRITES3         (HWRITES3),
    .HSIZES3          (HSIZES3),
    .HBURSTS3         (HBURSTS3),
    .HPROTS3          (HPROTS3),
    .HWDATAS3         (HWDATAS3),
    .HMASTLOCKS3      (HMASTLOCKS3),
    .HAUSERS3         (HAUSERS3),
    .HWUSERS3         (HWUSERS3),
    // SI4 – CPU1 DCODE
    .HADDRS4          (HADDRS4),
    .HTRANSS4         (HTRANSS4),
    .HWRITES4         (HWRITES4),
    .HSIZES4          (HSIZES4),
    .HBURSTS4         (HBURSTS4),
    .HPROTS4          (HPROTS4),
    .HWDATAS4         (HWDATAS4),
    .HMASTLOCKS4      (HMASTLOCKS4),
    .HAUSERS4         (HAUSERS4),
    .HWUSERS4         (HWUSERS4),
    // SI5 – CPU1 SYSTEM
    .HADDRS5          (HADDRS5),
    .HTRANSS5         (HTRANSS5),
    .HWRITES5         (HWRITES5),
    .HSIZES5          (HSIZES5),
    .HBURSTS5         (HBURSTS5),
    .HPROTS5          (HPROTS5),
    .HWDATAS5         (HWDATAS5),
    .HMASTLOCKS5      (HMASTLOCKS5),
    .HAUSERS5         (HAUSERS5),
    .HWUSERS5         (HWUSERS5),
    // SI6 – DMA Read Bus
    .HADDRS6          (HADDRS6),
    .HTRANSS6         (HTRANSS6),
    .HWRITES6         (HWRITES6),
    .HSIZES6          (HSIZES6),
    .HBURSTS6         (HBURSTS6),
    .HPROTS6          (HPROTS6),
    .HWDATAS6         (HWDATAS6),
    .HMASTLOCKS6      (HMASTLOCKS6),
    .HAUSERS6         (HAUSERS6),
    .HWUSERS6         (HWUSERS6),
    // SI7 – DMA Write Bus
    .HADDRS7          (HADDRS7),
    .HTRANSS7         (HTRANSS7),
    .HWRITES7         (HWRITES7),
    .HSIZES7          (HSIZES7),
    .HBURSTS7         (HBURSTS7),
    .HPROTS7          (HPROTS7),
    .HWDATAS7         (HWDATAS7),
    .HMASTLOCKS7      (HMASTLOCKS7),
    .HAUSERS7         (HAUSERS7),
    .HWUSERS7         (HWUSERS7),
    // SI8 – unused (IDLE)
    .HADDRS8          (HADDRS8),
    .HTRANSS8         (HTRANSS8),
    .HWRITES8         (HWRITES8),
    .HSIZES8          (HSIZES8),
    .HBURSTS8         (HBURSTS8),
    .HPROTS8          (HPROTS8),
    .HWDATAS8         (HWDATAS8),
    .HMASTLOCKS8      (HMASTLOCKS8),
    .HAUSERS8         (HAUSERS8),
    .HWUSERS8         (HWUSERS8),
    // MI0 – slave responses from sram_a a0
    .HRDATAM0         (HRDATAM0),
    .HREADYOUTM0      (HREADYOUTM0),
    .HRESPM0          (HRESPM0),
    .HRUSERM0         (HRUSERM0),
    // MI1 – slave responses from sram_a a1
    .HRDATAM1         (HRDATAM1),
    .HREADYOUTM1      (HREADYOUTM1),
    .HRESPM1          (HRESPM1),
    .HRUSERM1         (HRUSERM1),
    // MI2 – slave responses from APB bridge
    .HRDATAM2         (HRDATAM2),
    .HREADYOUTM2      (HREADYOUTM2),
    .HRESPM2          (HRESPM2),
    .HRUSERM2         (HRUSERM2),
    // MI3 – slave responses from System SRAM
    .HRDATAM3         (HRDATAM3),
    .HREADYOUTM3      (HREADYOUTM3),
    .HRESPM3          (HRESPM3),
    .HRUSERM3         (HRUSERM3),
    // MI4 – slave responses from Wishbone memory 
    .HRDATAM4         (HRDATAM4),
    .HREADYOUTM4      (HREADYOUTM4),
    .HRESPM4          (HRESPM4),
    .HRUSERM4         (HRUSERM4),
    // MI5 – slave responses from EThernet MAC
    .HRDATAM5         (HRDATAM5),
    .HREADYOUTM5      (HREADYOUTM5),
    .HRESPM5          (HRESPM5),
    .HRUSERM5         (HRUSERM5),
    // Scan
    .SCANENABLE       (SCANENABLE),
    .SCANINHCLK       (SCANINHCLK),
    // MI0 – matrix→slave outputs (to sram_a a0)
    .HSELM0           (HSELM0),
    .HADDRM0          (HADDRM0),
    .HTRANSM0         (HTRANSM0),
    .HWRITEM0         (HWRITEM0),
    .HSIZEM0          (HSIZEM0),
    .HBURSTM0         (HBURSTM0),
    .HPROTM0          (HPROTM0),
    .HWDATAM0         (HWDATAM0),
    .HMASTLOCKM0      (HMASTLOCKM0),
    .HREADYMUXM0      (HREADYMUXM0),
    .HAUSERM0         (HAUSERM0),
    .HWUSERM0         (HWUSERM0),
    // MI1 – matrix→slave outputs (to sram_a a1)
    .HSELM1           (HSELM1),
    .HADDRM1          (HADDRM1),
    .HTRANSM1         (HTRANSM1),
    .HWRITEM1         (HWRITEM1),
    .HSIZEM1          (HSIZEM1),
    .HBURSTM1         (HBURSTM1),
    .HPROTM1          (HPROTM1),
    .HWDATAM1         (HWDATAM1),
    .HMASTLOCKM1      (HMASTLOCKM1),
    .HREADYMUXM1      (HREADYMUXM1),
    .HAUSERM1         (HAUSERM1),
    .HWUSERM1         (HWUSERM1),
    // MI2 – matrix→slave outputs (to APB bridge)
    .HSELM2           (HSELM2),
    .HADDRM2          (HADDRM2),
    .HTRANSM2         (HTRANSM2),
    .HWRITEM2         (HWRITEM2),
    .HSIZEM2          (HSIZEM2),
    .HBURSTM2         (HBURSTM2),
    .HPROTM2          (HPROTM2),
    .HWDATAM2         (HWDATAM2),
    .HMASTLOCKM2      (HMASTLOCKM2),
    .HREADYMUXM2      (HREADYMUXM2),
    .HAUSERM2         (HAUSERM2),
    .HWUSERM2         (HWUSERM2),
    // MI3 – matrix→slave outputs (to System SRAM)
    .HSELM3           (HSELM3),
    .HADDRM3          (HADDRM3),
    .HTRANSM3         (HTRANSM3),
    .HWRITEM3         (HWRITEM3),
    .HSIZEM3          (HSIZEM3),
    .HBURSTM3         (HBURSTM3),
    .HPROTM3          (HPROTM3),
    .HWDATAM3         (HWDATAM3),
    .HMASTLOCKM3      (HMASTLOCKM3),
    .HREADYMUXM3      (HREADYMUXM3),
    .HAUSERM3         (HAUSERM3),
    .HWUSERM3         (HWUSERM3),
    // MI4 – matrix->slave outputs (to wishbone memory)
    .HSELM4           (HSELM4),
    .HADDRM4          (HADDRM4),
    .HTRANSM4         (HTRANSM4),
    .HWRITEM4         (HWRITEM4),
    .HSIZEM4          (HSIZEM4),
    .HBURSTM4         (HBURSTM4),
    .HPROTM4          (HPROTM4),
    .HWDATAM4         (HWDATAM4),
    .HMASTLOCKM4      (HMASTLOCKM4),
    .HREADYMUXM4      (HREADYMUXM4),
    .HAUSERM4         (HAUSERM4),
    .HWUSERM4         (HWUSERM4),
    // MI5 – matrix->slave outputs (to Ethernet MAC) 
    .HSELM5           (HSELM5),
    .HADDRM5          (HADDRM5),
    .HTRANSM5         (HTRANSM5),
    .HWRITEM5         (HWRITEM5),
    .HSIZEM5          (HSIZEM5),
    .HBURSTM5         (HBURSTM5),
    .HPROTM5          (HPROTM5),
    .HWDATAM5         (HWDATAM5),
    .HMASTLOCKM5      (HMASTLOCKM5),
    .HREADYMUXM5      (HREADYMUXM5),
    .HAUSERM5         (HAUSERM5),
    .HWUSERM5         (HWUSERM5),
    // SI0 response → CPU0 ICODE
    .HRDATAS0         (HRDATAS0),
    .HREADYS0         (HREADYS0),
    .HRESPS0          (HRESPS0),
    .HRUSERS0         (HRUSERS0),
    // SI1 response → CPU0 DCODE
    .HRDATAS1         (HRDATAS1),
    .HREADYS1         (HREADYS1),
    .HRESPS1          (HRESPS1),
    .HRUSERS1         (HRUSERS1),
    // SI2 response → CPU1 ICODE
    .HRDATAS2         (HRDATAS2),
    .HREADYS2         (HREADYS2),
    .HRESPS2          (HRESPS2),
    .HRUSERS2         (HRUSERS2),
    // SI3 response → CPU0 SYSTEM
    .HRDATAS3         (HRDATAS3),
    .HREADYS3         (HREADYS3),
    .HRESPS3          (HRESPS3),
    .HRUSERS3         (HRUSERS3),
    // SI4 response → CPU1 DCODE
    .HRDATAS4         (HRDATAS4),
    .HREADYS4         (HREADYS4),
    .HRESPS4          (HRESPS4),
    .HRUSERS4         (HRUSERS4),
    // SI5 response → CPU1 SYSTEM
    .HRDATAS5         (HRDATAS5),
    .HREADYS5         (HREADYS5),
    .HRESPS5          (HRESPS5),
    .HRUSERS5         (HRUSERS5),
    // SI6-SI8 responses (unconnected)
    .HRDATAS6         (HRDATAS6),
    .HREADYS6         (HREADYS6),
    .HRESPS6          (HRESPS6),
    .HRUSERS6         (HRUSERS6),
    .HRDATAS7         (HRDATAS7),
    .HREADYS7         (HREADYS7),
    .HRESPS7          (HRESPS7),
    .HRUSERS7         (HRUSERS7),
    .HRDATAS8         (HRDATAS8),
    .HREADYS8         (HREADYS8),
    .HRESPS8          (HRESPS8),
    .HRUSERS8         (HRUSERS8),
    .SCANOUTHCLK      (SCANOUTHCLK)
  );

  `ifdef PRINTF_ENABLE
    sim_stdout_monitor (
	  .HCLK(HCLK),
	  .HRESETn(HRESETn),
	  .HADDRS(HADDRS3),
	  .HWDATAS(HWDATAS3),
	  .HWRITES(HWRITES3),
	  .HTRANSS(HTRANSS3),
	  .HREADYS(HREADYS3)
	  );
  `endif

  //==========================================================================
  // SRAM A0 – Code/Data SRAM, connected to MI0
  // Shared by both CPUs for code / constant-data fetches via the matrix.
  //==========================================================================
  assign CLK_SRAMA0       = HCLK;
  assign ADDR_SRAMA0      = SRAMADDR_SRAMA0;
  assign WDATA_SRAMA0     = SRAMWDATA_SRAMA0;
  assign WREN_SRAMA0      = SRAMWEN_SRAMA0;
  assign CS_SRAMA0        = SRAMCS_SRAMA0;

  cmsdk_fpga_sram #(.AW(SRAMA_AW)) cmsdk_fpga_sram_A0 (
    .CLK   (CLK_SRAMA0),
    .ADDR  (ADDR_SRAMA0),
    .WDATA (WDATA_SRAMA0),
    .WREN  (WREN_SRAMA0),
    .CS    (CS_SRAMA0),
    .RDATA (RDATA_SRAMA0)
  );

  assign HCLK_SRAMA0       = HCLK;
  assign HRESETn_SRAMA0    = HRESETn;
  assign SRAMRDATA_SRAMA0  = RDATA_SRAMA0;
  assign HSEL_SRAMA0       = HSELM0;
  assign HREADY_SRAMA0     = HREADYMUXM0;
  assign HTRANS_SRAMA0     = HTRANSM0;
  assign HSIZE_SRAMA0      = HSIZEM0;
  assign HWRITE_SRAMA0     = HWRITEM0;
  assign HADDR_SRAMA0      = HADDRM0[SRAMA_AW-1:0];
  assign HWDATA_SRAMA0     = HWDATAM0;

  cmsdk_ahb_to_sram #(.AW(SRAMA_AW)) cmsdk_ahb_to_sram_A0 (
    .HCLK      (HCLK_SRAMA0),
    .HRESETn   (HRESETn_SRAMA0),
    .HSEL      (HSEL_SRAMA0),
    .HREADY    (HREADY_SRAMA0),
    .HTRANS    (HTRANS_SRAMA0),
    .HSIZE     (HSIZE_SRAMA0),
    .HWRITE    (HWRITE_SRAMA0),
    .HADDR     (HADDR_SRAMA0),
    .HWDATA    (HWDATA_SRAMA0),
    .HREADYOUT (HREADYOUT_SRAMA0),
    .HRESP     (HRESP_SRAMA0),
    .HRDATA    (HRDATA_SRAMA0),
    .SRAMRDATA (SRAMRDATA_SRAMA0),
    .SRAMADDR  (SRAMADDR_SRAMA0),
    .SRAMWEN   (SRAMWEN_SRAMA0),
    .SRAMWDATA (SRAMWDATA_SRAMA0),
    .SRAMCS    (SRAMCS_SRAMA0)
  );

  // MI0 responses from SRAM A0 bridge
  assign HRDATAM0    = HRDATA_SRAMA0;
  assign HREADYOUTM0 = HREADYOUT_SRAMA0;
  assign HRESPM0     = HRESP_SRAMA0;

  //==========================================================================
  // SRAM A1 – Code/Data SRAM, connected to MI1
  // CPU1-local memory; same capacity and interface as A0.
  //==========================================================================
  assign CLK_SRAMA1       = HCLK;
  assign ADDR_SRAMA1      = SRAMADDR_SRAMA1;
  assign WDATA_SRAMA1     = SRAMWDATA_SRAMA1;
  assign WREN_SRAMA1      = SRAMWEN_SRAMA1;
  assign CS_SRAMA1        = SRAMCS_SRAMA1;

  cmsdk_fpga_sram #(.AW(SRAMA_AW)) cmsdk_fpga_sram_A1 (
    .CLK   (CLK_SRAMA1),
    .ADDR  (ADDR_SRAMA1),
    .WDATA (WDATA_SRAMA1),
    .WREN  (WREN_SRAMA1),
    .CS    (CS_SRAMA1),
    .RDATA (RDATA_SRAMA1)
  );

  assign HCLK_SRAMA1       = HCLK;
  assign HRESETn_SRAMA1    = HRESETn;
  assign SRAMRDATA_SRAMA1  = RDATA_SRAMA1;
  assign HSEL_SRAMA1       = HSELM1;
  assign HREADY_SRAMA1     = HREADYMUXM1;
  assign HTRANS_SRAMA1     = HTRANSM1;
  assign HSIZE_SRAMA1      = HSIZEM1;
  assign HWRITE_SRAMA1     = HWRITEM1;
  assign HADDR_SRAMA1      = HADDRM1[SRAMA_AW-1:0];
  assign HWDATA_SRAMA1     = HWDATAM1;

  cmsdk_ahb_to_sram #(.AW(SRAMA_AW)) cmsdk_ahb_to_sram_A1 (
    .HCLK      (HCLK_SRAMA1),
    .HRESETn   (HRESETn_SRAMA1),
    .HSEL      (HSEL_SRAMA1),
    .HREADY    (HREADY_SRAMA1),
    .HTRANS    (HTRANS_SRAMA1),
    .HSIZE     (HSIZE_SRAMA1),
    .HWRITE    (HWRITE_SRAMA1),
    .HADDR     (HADDR_SRAMA1),
    .HWDATA    (HWDATA_SRAMA1),
    .HREADYOUT (HREADYOUT_SRAMA1),
    .HRESP     (HRESP_SRAMA1),
    .HRDATA    (HRDATA_SRAMA1),
    .SRAMRDATA (SRAMRDATA_SRAMA1),
    .SRAMADDR  (SRAMADDR_SRAMA1),
    .SRAMWEN   (SRAMWEN_SRAMA1),
    .SRAMWDATA (SRAMWDATA_SRAMA1),
    .SRAMCS    (SRAMCS_SRAMA1)
  );

  // MI1 responses from SRAM A1 bridge
  assign HRDATAM1    = HRDATA_SRAMA1;
  assign HREADYOUTM1 = HREADYOUT_SRAMA1;
  assign HRESPM1     = HRESP_SRAMA1;

  //==========================================================================
  // System SRAM (SRAMS) – MI3
  //==========================================================================
  assign CLK_SRAMS      = HCLK;
  assign ADDR_SRAMS     = SRAMADDR_SRAMS;
  assign WDATA_SRAMS    = SRAMWDATA_SRAMS;
  assign WREN_SRAMS     = SRAMWEN_SRAMS;
  assign CS_SRAMS       = SRAMCS_SRAMS;

  cmsdk_fpga_sram #(.AW(SRAMS_AW)) cmsdk_fpga_sram_S (
    .CLK   (CLK_SRAMS),
    .ADDR  (ADDR_SRAMS),
    .WDATA (WDATA_SRAMS),
    .WREN  (WREN_SRAMS),
    .CS    (CS_SRAMS),
    .RDATA (RDATA_SRAMS)
  );

  assign HCLK_SRAMS      = HCLK;
  assign HRESETn_SRAMS   = HRESETn;
  assign SRAMRDATA_SRAMS = RDATA_SRAMS;
  assign HSEL_SRAMS      = HSELM3;
  assign HREADY_SRAMS    = HREADYMUXM3;
  assign HTRANS_SRAMS    = HTRANSM3;
  assign HSIZE_SRAMS     = HSIZEM3;
  assign HWRITE_SRAMS    = HWRITEM3;
  assign HADDR_SRAMS     = HADDRM3;
  assign HWDATA_SRAMS    = HWDATAM3;

  cmsdk_ahb_to_sram #(.AW(SRAMS_AW)) cmsdk_ahb_to_sram_S (
    .HCLK      (HCLK_SRAMS),
    .HRESETn   (HRESETn_SRAMS),
    .HSEL      (HSEL_SRAMS),
    .HREADY    (HREADY_SRAMS),
    .HTRANS    (HTRANS_SRAMS),
    .HSIZE     (HSIZE_SRAMS),
    .HWRITE    (HWRITE_SRAMS),
    .HADDR     (HADDR_SRAMS),
    .HWDATA    (HWDATA_SRAMS),
    .HREADYOUT (HREADYOUT_SRAMS),
    .HRESP     (HRESP_SRAMS),
    .HRDATA    (HRDATA_SRAMS),
    .SRAMRDATA (SRAMRDATA_SRAMS),
    .SRAMADDR  (SRAMADDR_SRAMS),
    .SRAMWEN   (SRAMWEN_SRAMS),
    .SRAMWDATA (SRAMWDATA_SRAMS),
    .SRAMCS    (SRAMCS_SRAMS)
  );

  // MI3 response from System SRAM bridge
  assign HRDATAM3    = HRDATA_SRAMS;
  assign HREADYOUTM3 = HREADYOUT_SRAMS;
  assign HRESPM3     = HRESP_SRAMS;

  //==========================================================================
  // APB bridge – MI2
  //==========================================================================
  assign Hclk_b     = HCLK;
  assign Hprot_b    = HPROTM2;
  assign Hsel_b     = HSELM2;
  assign Hrst_b     = HRESETn;
  assign Hwrite_b   = HWRITEM2;
  assign Hreadyin_b = HREADYMUXM2;
  assign Hwdata_b   = HWDATAM2;
  assign Haddr_b    = HADDRM2;
  assign Hsize_b    = HSIZEM2;
  assign Htrans_b   = HTRANSM2;

  // MI2 response from APB bridge
  assign HRDATAM2    = Hrdata_b;
  assign HREADYOUTM2 = Hreadyout_b;
  assign HRESPM2     = Hresp_b;

  // Address-decode: qualify with PSEL_b so PSELx only asserts during valid phases
  assign PSEL_M    = Psel_b &  (Paddr_b[15:12] == 4'h0);
  assign PSEL_I2C  = Psel_b &  (Paddr_b[15:12] == 4'h1);
  assign PSELU     = Psel_b &  (Paddr_b[15:12] == 4'h2);
  assign PSEL_DMA  = Psel_b & ((Paddr_b[15:12] == 4'h3) | (Paddr_b[15:12] == 4'h4));

  // Peripheral read-data / ready mux – priority: DMA > UART > I2C > MEM
  assign Prdata_b  = PSEL_DMA  ? PRDATA_DMA  :
                     PSELU     ? PRDATAU     :
                     PSEL_I2C  ? PRDATA_I2C  : PRDATA_M;

  assign Pready_b  = PSEL_DMA  ? PREADY_DMA  :
                     PSELU     ? PREADYU     :
                     PSEL_I2C  ? PREADY_I2C  : PREADY_M;

  assign Pslverr_b = PSEL_DMA  ? PSLVERR_DMA :
                     PSELU     ? PSLVERRU    :
                     PSEL_I2C  ? PSLVERR_I2C : PSLVERR_M;
 
  cmsdk_ahb_to_apb #(.ADDRWIDTH (32)) bridge_ip (
    .HCLK      (Hclk_b),
    .HRESETn   (Hrst_b),
    .PCLKEN    (1'b1), // PCLK == HCLK; tie PCLKEN high
    // AHB slave port (from matrix MI2)
    .HSEL      (Hsel_b),
    .HADDR     (Haddr_b),
    .HTRANS    (Htrans_b),
    .HSIZE     (Hsize_b),
    .HPROT     (Hprot_b),
    .HWRITE    (Hwrite_b),
    .HREADY    (Hreadyin_b),
    .HWDATA    (Hwdata_b),
    // AHB slave responses → matrix MI2
    .HREADYOUT (Hreadyout_b),
    .HRDATA    (Hrdata_b),
    .HRESP     (Hresp_b),
    // APB master outputs → peripherals
    .PADDR     (Paddr_b),
    .PENABLE   (Penable_b),
    .PWRITE    (Pwrite_b),
    .PSTRB     (Pstrb_b),
    .PPROT     (Pprot_b),
    .PWDATA    (Pwdata_b),
    .PSEL      (Psel_b),
    .APBACTIVE (APBACTIVE_b),
    // APB slave inputs ← muxed from peripherals
    .PRDATA    (Prdata_b),
    .PREADY    (Pready_b),
    .PSLVERR   (Pslverr_b)
  );

  //==========================================================================
  //AHB TO WB BRIDGE (M4)
  //==========================================================================
  assign Hclk_ahb2wb = HCLK;
  assign Hrst_ahb2wb = HRESETn;
  assign Hwrite_ahb2wb = HWRITEM4; 
  assign Hreadyin_ahb2wb = HREADYMUXM4;
  assign Hwdata_ahb2wb = HWDATAM4; 
  assign Haddr_ahb2wb = HADDRM4; 
  assign Htrans_ahb2wb = HTRANSM4;
  assign Hsize_ahb2wb = HSIZEM4;
  assign HREADYOUTM4 = Hreadyout_ahb2wb;
  assign HRESPM4 = Hresp_ahb2wb;
  assign HRDATAM4 = Hrdata_ahb2wb;

  ahb_to_wishbone#(.BASE_ADDR(32'h5000_0000),
                   .UPPER_BOUNDARY(32'h507F_FFFF)
                 ) ahb_to_wb_bridge_ip (
	.HCLK(Hclk_ahb2wb),
	.HRESETn(Hrst_ahb2wb),
	.HADDR(Haddr_ahb2wb),
	.HTRANS(Htrans_ahb2wb),
	.HWRITE(Hwrite_ahb2wb),
	.HSIZE(Hsize_ahb2wb),
  .HSEL(HSELM4),
	.HWDATA(Hwdata_ahb2wb),
	.HREADYin(Hreadyin_ahb2wb),
	.HRDATA(Hrdata_ahb2wb),
	.HRESP(Hresp_ahb2wb),
	.HREADYout(Hreadyout_ahb2wb),
  .WB_ADR_O(adr_o_ahb2wb),
  .WB_DAT_O(dat_o_ahb2wb),
  .WB_DAT_I(dat_i_ahb2wb),
  .WB_ACK_I(ack_i_ahb2wb),
  .WB_ERR_I(err_i_ahb2wb),
  .WB_CYC_O(cyc_o_ahb2wb),
  .WB_WE_O(we_o_ahb2wb),
  .WB_STB_O(stb_o_ahb2wb),
  .WB_SEL_O(sel_o_ahb2wb)
);


  //==========================================================================
  // WISHBONE MENORY
  //==========================================================================
  assign WB_CLK_M = HCLK;
  assign WB_RST_M = ~HRESETn;
  assign WB_ADR_M = adr_o_ahb2wb;
  assign WB_DAT_M_I = dat_o_ahb2wb;
  assign dat_i_ahb2wb = WB_DAT_M_O;
  assign WB_SEL_M = sel_o_ahb2wb;
  assign WB_WE_M = we_o_ahb2wb;
  assign WB_CYC_M = cyc_o_ahb2wb;
  assign WB_STB_M = stb_o_ahb2wb;
  assign ack_i_ahb2wb = WB_ACK_M;
  assign err_i_ahb2wb = WB_ERR_M;

wb_memory #(
    .SIZE   (8*1024*1024),
    .WIDTH  (8),
    .AWIDTH (32),
    .DWIDTH (32)
) wb_memory_ip (
    .clk_i  (WB_CLK_M),
    .rst_i  (WB_RST_M),
    .adr_i  (WB_ADR_M),
    .dat_i  (WB_DAT_M_I),
    .dat_o  (WB_DAT_M_O),
    .sel_i  (WB_SEL_M),
    .we_i   (WB_WE_M),
    .cyc_i  (WB_CYC_M),
    .stb_i  (WB_STB_M),
    .ack_o  (WB_ACK_M),
    .err_o  (WB_ERR_M)
);

  //==========================================================================
  //AHB TO WB BRIDGE ETHERNET (M5)
  //==========================================================================
  assign mac_Hclk_ahb2wb = HCLK;
  assign mac_Hrst_ahb2wb = HRESETn;
  assign mac_Hwrite_ahb2wb = HWRITEM5; 
  assign mac_Hreadyin_ahb2wb = HREADYMUXM5;
  assign mac_Hwdata_ahb2wb = HWDATAM5; 
  assign mac_Haddr_ahb2wb = HADDRM5; 
  assign mac_Htrans_ahb2wb = HTRANSM5;
  assign mac_Hsize_ahb2wb = HSIZEM5;
  assign HREADYOUTM5 = mac_Hreadyout_ahb2wb;
  assign HRESPM5 = mac_Hresp_ahb2wb;
  assign HRDATAM5 = mac_Hrdata_ahb2wb;
  
  ahb_to_wishbone#(.BASE_ADDR(32'h5080_0000),
                   .UPPER_BOUNDARY(32'h509F_FFFF)
                 ) mac_ahb_to_wb_bridge_ip (
	.HCLK(mac_Hclk_ahb2wb),
	.HRESETn(mac_Hrst_ahb2wb),
	.HADDR(mac_Haddr_ahb2wb),
	.HTRANS(mac_Htrans_ahb2wb),
	.HWRITE(mac_Hwrite_ahb2wb),
	.HSIZE(mac_Hsize_ahb2wb),
  .HSEL(HSELM5),
	.HWDATA(mac_Hwdata_ahb2wb),
	.HREADYin(mac_Hreadyin_ahb2wb),
	.HRDATA(mac_Hrdata_ahb2wb),
	.HRESP(mac_Hresp_ahb2wb),
	.HREADYout(mac_Hreadyout_ahb2wb),
  .WB_ADR_O(mac_adr_o_ahb2wb),
  .WB_DAT_O(mac_dat_o_ahb2wb),
  .WB_DAT_I(mac_dat_i_ahb2wb),
  .WB_ACK_I(mac_ack_i_ahb2wb),
  .WB_ERR_I(mac_err_i_ahb2wb),
  .WB_CYC_O(mac_cyc_o_ahb2wb),
  .WB_WE_O(mac_we_o_ahb2wb),
  .WB_STB_O(mac_stb_o_ahb2wb),
  .WB_SEL_O(mac_sel_o_ahb2wb)
);

  //==========================================================================
  //WB TO AHB BRIDGE ETHERNET (S8)
  //==========================================================================
  wishbone_to_ahb(
  .HCLK(HCLK),
  .HRESETn(HRESETn),
  .WB_CYC_I(mac_cyc_i_wb2ahb),     
  .WB_STB_I(mac_stb_i_wb2ahb),     
  .WB_WE_I(mac_we_i_wb2ahb),      
  .WB_ADR_I(mac_adr_i_wb2ahb),     
  .WB_DAT_I(mac_dat_i_wb2ahb),     
  .WB_SEL_I(mac_sel_i_wb2ahb),     
  .WB_DAT_O(mac_dat_o_wb2ahb),     
  .WB_ACK_O(mac_ack_o_wb2ahb),     
  .WB_ERR_O(mac_err_o_wb2ahb),
  .HSEL(),
  .HADDR(HADDRS8),
  .HWDATA(HWDATAS8),
  .HTRANS(HTRANSS8),
  .HSIZE(HSIZES8),
  .HWRITE(HWRITES8),
  .HREADYout(),    
  .HRDATA(HRDATAS8),
  .HRESP(HRESPS8),
  .HREADYin(HREADYS8)
);


//====================================================================================
//Address remaping for accessing buffer descriptors inside the MAC
//====================================================================================
wire [31:0] MAC_ADDRESS;
assign MAC_ADDRESS = (mac_adr_o_ahb2wb >> 2);

  //==========================================================================
  // Ethernet MAC
  //==========================================================================
  assign mac_tx_clk = HCLK;
  assign mac_rx_clk = HCLK;
  assign INTISR[2]  = mac_intr_w;

ethmac Ethernet_MAC ( 
    // --------------------------------------------------
    // Wishbone common
    // --------------------------------------------------
    .wb_clk_i (mac_Hclk_ahb2wb),
    .wb_rst_i (!mac_Hrst_ahb2wb),

    .wb_dat_i (mac_dat_o_ahb2wb),
    .wb_dat_o (mac_dat_i_ahb2wb),

    // --------------------------------------------------
    // Wishbone SLAVE (MAC)
    // --------------------------------------------------
    .wb_adr_i (MAC_ADDRESS),
    .wb_sel_i (mac_sel_o_ahb2wb),
    .wb_we_i  (mac_we_o_ahb2wb),
    .wb_cyc_i (mac_cyc_o_ahb2wb),
    .wb_stb_i (mac_stb_o_ahb2wb),
    .wb_ack_o (mac_ack_i_ahb2wb),
    .wb_err_o (mac_err_i_ahb2wb),

    // --------------------------------------------------
    // Wishbone MASTER (MAC ? Memory)
    // --------------------------------------------------
    .m_wb_adr_o (mac_adr_i_wb2ahb),
    .m_wb_sel_o (mac_sel_i_wb2ahb),
    .m_wb_we_o  (mac_we_i_wb2ahb),
    .m_wb_dat_o (mac_dat_i_wb2ahb),
    .m_wb_dat_i (mac_dat_o_wb2ahb),
    .m_wb_cyc_o (mac_cyc_i_wb2ahb),
    .m_wb_stb_o (mac_stb_i_wb2ahb),
    .m_wb_ack_i (mac_ack_o_wb2ahb),
    .m_wb_err_i (mac_err_o_wb2ahb),

    // (Optional  if used)
    .m_wb_cti_o (),
    .m_wb_bte_o (),

    // --------------------------------------------------
    // PHY TX
    // --------------------------------------------------
    .mtx_clk_pad_i (mac_tx_clk),
    .mtxd_pad_o    (mac_txd),
    .mtxen_pad_o   (mac_tx_en),
    .mtxerr_pad_o  (mac_tx_err),
    .mcoll_pad_i   (mac_col),
    .mcrs_pad_i    (mac_crs),

    // --------------------------------------------------
    // PHY RX 
    // --------------------------------------------------
    .mrx_clk_pad_i (mac_rx_clk),
    .mrxd_pad_i    (mac_rxd),
    .mrxdv_pad_i   (mac_rx_dv),
    .mrxerr_pad_i  (mac_rx_err),

    // --------------------------------------------------
    // MIIM
    // --------------------------------------------------
    .mdc_pad_o   (mdc),
    .md_pad_i    (mdi),
    .md_pad_o    (mdo),
    .md_padoe_o  (mdoe),

    // --------------------------------------------------
    // Interrupt
    // --------------------------------------------------
    .int_o (mac_intr_w)
  ); 

  //==========================================================================
  // UART
  //==========================================================================
  assign INTISR[0] = uart_int_w;   // UART event → IRQ[0] for both CPUs

  assign PCLKU    = HCLK;
  assign PRSTU    = HRESETn;
  assign PADDRU   = Paddr_b;
  assign PWDATAU  = Pwdata_b;    // fixed: was incorrectly PWDATA in original
  assign PENABLEU = Penable_b;
  assign PWRITEU  = Pwrite_b;
  assign PSTRBU   = Pstrb_b;

 // UART DMA wires for pheripheral connection
  wire uart_tx_dma_req;
  wire uart_rx_dma_req;
  wire uart_tx_dma_clr;
  wire uart_rx_dma_clr;

  // I2C DMA wires for pheripheral connection
  wire i2c_tx_dma_req;
  wire i2c_rx_dma_req;
  wire i2c_tx_dma_clr;
  wire i2c_rx_dma_clr;

  apb_uart_sv #(.APB_ADDR_WIDTH(12)) uart_ip (
    .CLK     (PCLKU),
    .RSTN    (PRSTU),
    .PADDR   (PADDRU),
    .PWDATA  (PWDATAU),
    .PWRITE  (PWRITEU),
    .PSEL    (PSELU),
    .PSTRB   (PSTRBU),
    .PENABLE (PENABLEU),
    .PRDATA  (PRDATAU),
    .PREADY  (PREADYU),
    .PSLVERR (PSLVERRU),
    .rx_i    (RX_i_AU),
    .tx_o    (TX_o_AU),
    .event_o (uart_int_w),
    .tx_dma_req_o(uart_tx_dma_req),
    .rx_dma_req_o(uart_rx_dma_req),
    .tx_dma_clr_i(uart_tx_dma_clr),
    .rx_dma_clr_i(uart_rx_dma_clr)

  );

  //==========================================================================
  // I2C
  //==========================================================================
  wire i2c_int_tx;
  wire i2c_int_rx;
  wire PSLVERR_I2C;
  wire SDA_ENABLE_I2C;
  wire SCL_ENABLE_I2C;

  assign INTISR[3] = i2c_int_tx;   // I2C TX FIFO empty interrupt → IRQ[3] for both CPUs
  assign INTISR[4] = i2c_int_rx;   // I2C RX FIFO full interrupt  → IRQ[4] for both CPUs

  assign PCLK_I2C    = HCLK;
  assign PRESETn_I2C = HRESETn;
  assign PADDR_I2C   = Paddr_b - 32'h4000_1000;
  assign PWDATA_I2C  = Pwdata_b;
  assign PENABLE_I2C = Penable_b;
  assign PWRITE_I2C  = Pwrite_b;

  i2c i2c_ip (
    .PCLK       (PCLK_I2C),
    .PRESETn    (PRESETn_I2C),
    .PADDR      (PADDR_I2C),
    .PWDATA     (PWDATA_I2C),
    .PWRITE     (PWRITE_I2C),
    .PSELx      (PSEL_I2C),
    .PENABLE    (PENABLE_I2C),
    .PREADY     (PREADY_I2C),
    .PSLVERR    (PSLVERR_I2C),
    .INT_RX     (i2c_int_rx),
    .INT_TX     (i2c_int_tx),
    .PRDATA     (PRDATA_I2C),
    .SDA_ENABLE (SDA_ENABLE_I2C),
    .SCL_ENABLE (SCL_ENABLE_I2C),
    .SDA        (SDA_o),
    .SCL        (SCL_o),
    .tx_dma_req_o(i2c_tx_dma_req),
    .rx_dma_req_o(i2c_rx_dma_req),
    .tx_dma_clr_i(i2c_tx_dma_clr),
    .rx_dma_clr_i(i2c_rx_dma_clr)
  );

  //==========================================================================
  // APB memory
  //==========================================================================
  assign PCLK_M    = HCLK;
  assign PRST_M    = ~HRESETn;
  assign PADDR_M   = Paddr_b;
  assign PWDATA_M  = Pwdata_b;
  assign PWRITE_M  = Pwrite_b;
  assign PENABLE_M = Penable_b;
  assign PSTRB_M   = Pstrb_b;
  assign PSLVERR_M = 1'b0;
  apb_memory mem_ip (
    .clk_i   (PCLK_M),
    .rst_i   (PRST_M),
    .addr_i  (PADDR_M),
    .wdata_i (PWDATA_M),
    .wr_rd_i (PWRITE_M),
    .sel_i   (PSEL_M),
    .valid_i (PENABLE_M),
    .strb_i  (PSTRB_M),
    .rdata_o (PRDATA_M),
    .ready_o (PREADY_M)
  );

  //==========================================================================
  // DMA – dma_ahb32
  //   APB config  : (0x4000_3000–0x4000_4FFF)
  //   Read  master: SI6 (RH* ports)
  //   Write master: SI7 (WH* ports)
  //   INT         : INTISR[1]
  //   periph_*    : left for user connection
  //==========================================================================
  assign INTISR[1]   = dma_int_w;  // DMA  INT   → IRQ[1] for both CPUs
  assign PADDR_DMA   = Paddr_b - 32'h4000_3000;
  assign PWDATA_DMA  = Pwdata_b;
  assign PWRITE_DMA  = Pwrite_b;
  assign PENABLE_DMA = Penable_b; 
  wire[31:1] dma_tx_clr_bus;
  wire[31:1] dma_rx_clr_bus;

  // Clear signal for the UART
  assign uart_tx_dma_clr= dma_tx_clr_bus[1];
  assign uart_rx_dma_clr= dma_rx_clr_bus[1];

  // Clear signal for the I2C
  assign i2c_tx_dma_clr= dma_tx_clr_bus[2];
  assign i2c_rx_dma_clr= dma_rx_clr_bus[2];

  dma_ahb32 dma_ip (
    // Clk / reset
    .clk          (HCLK),
    .reset        (~HRESETn),        // active-high reset

    // Scan
    .scan_en      (1'b0),

    // Status outputs
    .idle         (DMA_IDLE),        // declare wire DMA_IDLE; connect as needed

    // Interrupt
    .INT          (dma_int_w),       // → INTISR[1]

    // Peripheral handshake 
    .periph_tx_req  ({29'b0,i2c_tx_dma_req,uart_tx_dma_req}),
    .periph_tx_clr  (uart_tx_dma_clr),
    .periph_rx_req  ({29'b0,i2c_rx_dma_req,uart_rx_dma_req}),
    .periph_rx_clr  (uart_rx_dma_clr),

    // APB slave interface (config registers)
    .pclken       (1'b1),            // always-enabled APB clock
    .psel         (PSEL_DMA),
    .penable      (PENABLE_DMA),
    .paddr        (PADDR_DMA),
    .pwrite       (PWRITE_DMA),
    .pwdata       (PWDATA_DMA),
    .prdata       (PRDATA_DMA),
    .pslverr      (PSLVERR_DMA),
    .pready       (PREADY_DMA),

    // AHB write master → SI7
    .WHADDR0      (HADDRS7),
    .WHBURST0     (HBURSTS7),
    .WHSIZE0      (HSIZES7),
    .WHTRANS0     (HTRANSS7),
    .WHWDATA0     (HWDATAS7),
    .WHREADY0     (HREADYS7),        // ← matrix HREADYS7
    .WHRESP0      (HRESPS7),         // ← matrix HRESPS7

    // AHB read master → SI6
    .RHADDR0      (HADDRS6),
    .RHBURST0     (HBURSTS6),
    .RHSIZE0      (HSIZES6),
    .RHTRANS0     (HTRANSS6),
    .RHRDATA0     (HRDATAS6),        // ← matrix HRDATAS6
    .RHREADY0     (HREADYS6),        // ← matrix HREADYS6
    .RHRESP0      (HRESPS6)          // ← matrix HRESPS6
  );

  //==========================================================================
  // Bus-matrix SI → CPU feedback connections
  //==========================================================================

  // CPU0 ICODE feedback ← matrix SI0
  assign HREADYI = HREADYS0;
  assign HRDATAI = HRDATAS0;
  assign HRESPI  = HRESPS0;     // 1-bit→2-bit: zero-extended

  // CPU0 DCODE feedback ← matrix SI1
  assign HREADYD = HREADYS1;
  assign HRDATAD = HRDATAS1;
  assign HRESPD  = HRESPS1;

  // CPU0 SYSTEM feedback ← matrix SI3
  assign HREADYS = HREADYS3;
  assign HRDATAS = HRDATAS3;
  assign HRESPS  = HRESPS3;

  // CPU1 ICODE/DCODE/SYSTEM feedbacks are wired directly in the i1 port map
  // (HREADYS3→.HREADYI, HRDATAS3→.HRDATAI, etc.).

  //==========================================================================
  // CPU0 AHB bus → bus matrix slave-port inputs
  //==========================================================================

  // SI0 – CPU0 ICODE (read-only; HMASTLOCK not relevant in 0x0-0x1FFF_FFFF)
  assign HADDRS0     = HADDRI;
  assign HTRANSS0    = HTRANSI;
  assign HWRITES0    = 1'b0;        // ICODE is a fetch-only bus
  assign HSIZES0     = HSIZEI;
  assign HBURSTS0    = HBURSTI;
  assign HPROTS0     = HPROTI;
  assign HWDATAS0    = 32'h0;
  assign HMASTLOCKS0 = 1'b0;
  assign HAUSERS0    = 32'h0;
  assign HWUSERS0    = 32'h0;

  // SI1 – CPU0 DCODE
  assign HADDRS1     = HADDRD;
  assign HTRANSS1    = HTRANSD;
  assign HWRITES1    = HWRITED;
  assign HSIZES1     = HSIZED;
  assign HBURSTS1    = HBURSTD;
  assign HPROTS1     = HPROTD;
  assign HWDATAS1    = HWDATAD;
  assign HMASTLOCKS1 = 1'b0;
  assign HAUSERS1    = 32'h0;
  assign HWUSERS1    = 32'h0;

  // SI3 – CPU0 SYSTEM BUS
  assign HADDRS3     = HADDRS;
  assign HTRANSS3    = HTRANSS;
  assign HWRITES3    = HWRITES;
  assign HSIZES3     = HSIZES;
  assign HBURSTS3    = HBURSTS;
  assign HPROTS3     = HPROTS;
  assign HWDATAS3    = HWDATAS;
  assign HMASTLOCKS3 = 1'b0;   // no bit-band in 0x2000_0000-0x2FFF_FFFF
  assign HAUSERS3    = 32'h0;
  assign HWUSERS3    = 32'h0;

  //==========================================================================
  // CPU1 AHB bus → bus matrix slave-port inputs
  //
  // Address remapping for CPU1
  // ─────────────────────────────────────────────────────────────────────────
  // ICODE / DCODE: 0x1000_0000–0x1000_FFFF  →  0x0000_0000–0x0000_FFFF
  //   CPU1 code is linked at 0x1000_0000 so it lands in its own sram_A1,
  //   but the physical fetch is redirected to 0x0000_0000 where the same
  //   startup image lives (shared with CPU0 in SRAM_S / sram_A0).
  //
  // SYSTEM:        0x2000_0000–0x2000_0400  →  0x2000_0400–0x2000_0800
  //   Both CPUs share the same startup file: initial SP = 0x2000_0400,
  //   downward-growing. CPU0 stack occupies physical 0x2000_0000–0x2000_03FC.
  //   Remapping CPU1's logical 0x2000_0000–0x2000_0400 (+0x400 offset) shifts
  //   all CPU1 stack writes to physical 0x2000_0400–0x2000_07FC, and maps
  //   CPU1's logical SP value (0x2000_0400) to effective physical 0x2000_0800.
  //==========================================================================
 
  // --- ICODE remapper (SI3) ---
  wire [31:0] HADDRI_i1_r;
  assign HADDRI_i1_r = (HADDRI_i1[31:16] == 16'h0000)
                       ? {16'h1000, HADDRI_i1[15:0]}
                       : HADDRI_i1;
 
  // --- DCODE remapper (SI4) ---
  wire [31:0] HADDRD_i1_r;
  assign HADDRD_i1_r = (HADDRD_i1[31:16] == 16'h0000)
                       ? {16'h1000, HADDRD_i1[15:0]}
                       : HADDRD_i1;
 
  // --- SYSTEM remapper (SI5) ---
  // Both CPUs share the same startup: initial SP = 0x2000_0400, downward-growing.
  // CPU0 physical stack:  0x2000_0000 – 0x2000_03FC  (grows down from 0x2000_0400)
  // CPU1 physical stack:  0x2000_0400 – 0x2000_07FC  (grows down from 0x2000_0800)
  //
  // Source range: 0x2000_0000 – 0x2000_0400 (inclusive of SP init value)
  // Target range: 0x2000_0400 – 0x2000_0800  (+0x400 offset)
  //
  // Including 0x2000_0400 in the source is critical: it means CPU1's logical
  // SP (0x2000_0400) maps to physical 0x2000_0800, so the CPU1 stack region
  // is fully contained in 0x2000_0400–0x2000_07FC with no overlap into CPU0.
  wire [31:0] HADDRS_i1_r;
  assign HADDRS_i1_r = ((HADDRS_i1 >= 32'h2000_0000) && (HADDRS_i1 <= 32'h2000_0400))
                       ? (HADDRS_i1 + 32'h0000_0500)
                       : HADDRS_i1;

  //==========================================================================
  // CPU1 AHB bus → bus matrix slave-port inputs
  //==========================================================================

  // SI2 – CPU1 ICODE (read-only)
  assign HADDRS2     = HADDRI_i1_r;
  assign HTRANSS2    = HTRANSI_i1;
  assign HWRITES2    = 1'b0;
  assign HSIZES2     = HSIZEI_i1;
  assign HBURSTS2    = HBURSTI_i1;
  assign HPROTS2     = HPROTI_i1;
  assign HWDATAS2    = 32'h0;
  assign HMASTLOCKS2 = 1'b0;
  assign HAUSERS2    = 32'h0;
  assign HWUSERS2    = 32'h0;

  // SI4 – CPU1 DCODE
  assign HADDRS4     = HADDRD_i1_r;
  assign HTRANSS4    = HTRANSD_i1;
  assign HWRITES4    = HWRITED_i1;
  assign HSIZES4     = HSIZED_i1;
  assign HBURSTS4    = HBURSTD_i1;
  assign HPROTS4     = HPROTD_i1;
  assign HWDATAS4    = HWDATAD_i1;
  assign HMASTLOCKS4 = 1'b0;
  assign HAUSERS4    = 32'h0;
  assign HWUSERS4    = 32'h0;

  // SI5 – CPU1 SYSTEM BUS
  assign HADDRS5     = HADDRS_i1_r;
  assign HTRANSS5    = HTRANSS_i1;
  assign HWRITES5    = HWRITES_i1;
  assign HSIZES5     = HSIZES_i1;
  assign HBURSTS5    = HBURSTS_i1;
  assign HPROTS5     = HPROTS_i1;
  assign HWDATAS5    = HWDATAS_i1;
  assign HMASTLOCKS5 = 1'b0;
  assign HAUSERS5    = 32'h0;
  assign HWUSERS5    = 32'h0;

  //==========================================================================
  // DMA AHB master buses → bus matrix slave-port inputs
  //==========================================================================

  // SI6 – DMA read master (HWRITE always 0; HWDATA unused)
  // HADDRS6 / HTRANSS6 / HSIZES6 / HBURSTS6 / HWDATAS6 are driven by
  // dma_ip port connections above.
  assign HWRITES6    = 1'b0;        // read-only master
  assign HPROTS6     = 4'b0011;     // data access, privileged
  assign HMASTLOCKS6 = 1'b0;
  assign HAUSERS6    = 32'h0;
  assign HWUSERS6    = 32'h0;

  // SI7 – DMA write master (HWRITE always 1; HRDATA ignored by DMA)
  // HADDRS7 / HTRANSS7 / HSIZES7 / HBURSTS7 / HWDATAS7 are driven by
  // dma_ip port connections above.
  assign HWRITES7    = 1'b1;        // write-only master
  assign HPROTS7     = 4'b0011;     // data access, privileged
  assign HMASTLOCKS7 = 1'b0;
  assign HAUSERS7    = 32'h0;
  assign HWUSERS7    = 32'h0;

endmodule
