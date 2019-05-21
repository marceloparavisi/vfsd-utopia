/**********************************************************************
 * Functional coverage code
 *
 * Author: Chris Spear
 * Revision: 1.01
 * Last modified: 8/2/2011
 *
 * (c) Copyright 2008-2011, Chris Spear, Greg Tumbush. *** ALL RIGHTS RESERVED ***
 * http://chris.spear.net
 *
 *  This source file may be used and distributed without restriction
 *  provided that this copyright statement is not removed from the file
 *  and that any derivative work contains this copyright notice.
 *
 * Used with permission in the book, "SystemVerilog for Verification"
 * By Chris Spear and Greg Tumbush
 * Book copyright: 2008-2011, Springer LLC, USA, Springer.com
 *********************************************************************/

`ifndef COVERAGE__SV
`define COVERAGE__SV

import uvm_pkg::*;
`include "uvm_macros.svh"
`include "definitions.sv"

`include "uni_cell.sv"
`include "nni_cell.sv"
`include "wrapper_cell.sv"



class coverage extends uvm_subscriber #(wrapper_cell);
`uvm_component_utils(coverage);

	bit [1:0] srcRx;
	bit [NumTx-1:0] fwdRx;
	bit [1:0] srcTx;
	bit [NumTx-1:0] fwdTx;

	covergroup CG_Backward;

		coverpoint srcRx
			{bins srcRx[] = {[0:3]};
				option.weight = 0;}
		coverpoint fwdRx
			{bins fwdRx[] = {[1:15]}; // Ignore fwd==0
			 option.weight = 0;}
      		cross srcRx, fwdRx;
	endgroup: CG_Backward;

	covergroup CG_Forward;
		coverpoint srcTx
			{bins srcTx[] = {[0:3]};
				option.weight = 0;}
		coverpoint fwdTx
			{bins fwd[] = {[1:15]}; // Ignore fwd==0
			 option.weight = 0;}

      		TX_FWD_CROSS : cross srcTx, fwdTx
		{
			ignore_bins erroPorta = TX_FWD_CROSS with 
								((srcTx == 3 && fwdTx>=1 && fwdTx<=7) ||
								(srcTx == 2 && (
								        (fwdTx>=0 && fwdTx<=3) ||
									(fwdTx>=8 && fwdTx<=11)) ) ||
								(srcTx == 1 && (
								        fwdTx==1 || 
									fwdTx==4 ||
									fwdTx==5 ||
									fwdTx==8 ||
									fwdTx==9 ||
									fwdTx==12 ||
									fwdTx==13)) ||
								(srcTx == 0 && 
								        fwdTx%2==0));

		}
		ERRO_CROSS : cross srcTx, fwdTx
		{
			option.goal=0; // geracoes futuras, arrume aqui... Como fazer isso??
			ignore_bins corretosPorta = ERRO_CROSS with 
								((srcTx == 3 && fwdTx>=8 && fwdTx<=15) ||
								(srcTx == 2 && (
								        (fwdTx>=4 && fwdTx<=7) ||
									(fwdTx>=12 && fwdTx<=15)) ) ||
								(srcTx == 1 && (
								        fwdTx==2 || 
								        fwdTx==3 || 
									fwdTx==6 ||
									fwdTx==7 ||
									fwdTx==10 ||
									fwdTx==11 ||
									fwdTx==14 ||
									fwdTx==15)) ||
								(srcTx == 0 && 
								        fwdTx%2==1));

		}

   	endgroup : CG_Forward

     	// Instantiate the covergroup
     	
	extern function new(string name, uvm_component parent);
	extern function void write(wrapper_cell t);

endclass : coverage

function coverage::new(string name, uvm_component parent);
		super.new(name,parent);
		CG_Forward = new();
		CG_Backward = new();
endfunction : new

function void coverage::write(wrapper_cell t);
	if (t._io_type == wrapper_cell::OUTPUT_MONITOR)
	begin
		CellCfgType CellCfg;
		this.srcTx = t._portn;
		CellCfg= top.squat.lut.read(t._nni_cell.VPI);
		this.fwdTx = CellCfg.FWD;
		t._nni_cell.display($sformatf("coverage portn: %d fwd: %b. ", t._portn, this.fwdTx));
		CG_Forward.sample();
	end
	if (t._io_type == wrapper_cell::INPUT_MONITOR)
	begin
		CellCfgType CellCfg;
		this.srcRx = t._portn;

		CellCfg= top.squat.lut.read(t._uni_cell.VPI);
		this.fwdRx = CellCfg.FWD;
		$display("fwd: %d vpi: ", CellCfg.FWD, t._uni_cell.VPI);
		t._uni_cell.display($sformatf("coverage portn: %d fwd: %b[%d]. ", t._portn, this.fwdRx, t._uni_cell.VPI));
		CG_Backward.sample();
	end
endfunction: write 

`endif // COVERAGE__SV