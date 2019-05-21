

`ifndef SCOREBOARD__SV
`define SCOREBOARD__SV


import uvm_pkg::*;
`include "uvm_macros.svh"


`include "uni_cell.sv"
`include "nni_cell.sv"
`include "wrapper_cell.sv"

class Expect_cells;
   NNI_cell q[$];
   int iexpect, iactual;
endclass : Expect_cells

class scoreboard extends uvm_scoreboard;
`uvm_component_utils(scoreboard)
  uvm_analysis_imp#(UNI_cell, scoreboard) item_collected_export;


	uvm_analysis_port # (UNI_cell) in_mon_ap; // from input  monitor to sb
	uvm_analysis_port # (NNI_cell) out_mon_ap[`TxPorts]; // from output monitor to sb

	uvm_analysis_port #(wrapper_cell) cov_ap;  // used to send checker packets from the sb to the coverage

	uvm_tlm_analysis_fifo #(UNI_cell) input_fifo;
	uvm_tlm_analysis_fifo #(NNI_cell) output_fifo[`TxPorts];


	Expect_cells expect_cells[];
	// iexpect increases as UNI packages is generated
	// iactual increases as NNI packages is captured and was registered into expect_cells.q[]
	// iactual increases as NNI packages is captured and was NOT registered into expect_cells.q[]
	int iexpect, iactual, nErrors;
 	NNI_cell error_cells[$];
 
	extern function new(string name, uvm_component parent);
	extern function void build_phase(uvm_phase phase);
	extern function void connect_phase(uvm_phase phase);
	extern task run_phase(uvm_phase phase);
	extern task get_input_data(uvm_tlm_analysis_fifo #(UNI_cell) fifo, uvm_phase phase);
	extern task get_output_data(uvm_tlm_analysis_fifo #(NNI_cell) fifo, int portn, uvm_phase phase);
	extern virtual function void write(UNI_cell pkt);
	extern function void extract_phase( uvm_phase phase );
	extern function void display(string prefix);

// criar metodo de comparacao UNI_cell (entre o passivo e ativo)
endclass : scoreboard


// ----------------------------------- IMPLEMENTATION --------------------------------

  // new - constructor
function scoreboard::new (string name, uvm_component parent);
	super.new(name, parent);
endfunction : new

function void scoreboard::build_phase(uvm_phase phase);
	super.build_phase(phase);
	in_mon_ap = new( "in_mon_ap", this);
//	out_mon_ap = new( "out_mon_ap", this); 
	cov_ap = new( "cov_ap", this); 
	input_fifo  = new( "input_fifo", this); 
	nErrors=0;
	foreach (output_fifo[i])
	begin
		out_mon_ap[i] = new( $sformatf("out_mon_ap_%0d",i), this); 
		output_fifo[i] = new( $sformatf("output_fifo_%0d",i), this);
		uvm_config_db #(uvm_analysis_port #(NNI_cell) )::set(this, "", $sformatf("out_mon_ap_%0d",i), out_mon_ap[i]);
	end
	uvm_config_db #(uvm_analysis_port #(UNI_cell) )::set(this, "", "in_mon_ap", in_mon_ap);
	expect_cells = new[`TxPorts];
	foreach (expect_cells[i])
		expect_cells[i] = new();
endfunction : build_phase

function void scoreboard::connect_phase(uvm_phase phase);
	super.connect_phase(phase);
	in_mon_ap.connect(input_fifo.analysis_export);
	foreach (out_mon_ap[i])
		out_mon_ap[i].connect(output_fifo[i].analysis_export);
endfunction: connect_phase

// main task
task scoreboard::run_phase(uvm_phase phase);
  	fork
		get_input_data(input_fifo, phase);
		foreach (output_fifo[i])
		begin
			fork
				automatic int idx=i;
				begin
					get_output_data(output_fifo[idx], idx, phase);
				end
			join_none;
		end
		wait fork;
	join
endtask: run_phase

// task for input packets
task scoreboard::get_input_data(uvm_tlm_analysis_fifo #(UNI_cell) fifo, uvm_phase phase);

	UNI_cell tx;
	ATMCellType Pkt;
	CellCfgType CellCfg;
	forever begin
		int portn;
		NNI_cell ncell;
		fifo.get(tx);

		tx.pack(Pkt);
		phase.raise_objection(this);
		ncell = tx.to_NNI;
		CellCfg = top.squat.lut.read(tx.VPI);
		tx.display($sformatf("scoreboard received packet(FWD: %b)VPI %d: ",CellCfg.FWD, tx.VPI));
//		$display(" FWD: %b.", CellCfg.FWD);

		for (int i=0; i<`RxPorts; i++)
			if (CellCfg.FWD[i]) begin


				wrapper_cell wc;
				wc = wrapper_cell::type_id::create("w");
				// guardaando informacao para verificar se saiu
				expect_cells[i].q.push_back(ncell); // Save cell in this forward queue
				expect_cells[i].iexpect++;
				iexpect++;
				// enviando para coverage
				wc._portn = i;
				wc._uni_cell = tx;
				wc._io_type = wrapper_cell::INPUT_MONITOR;
				cov_ap.write(wc);
//				$write("\n############[%d]: %d ++", i, expect_cells[i].iexpect);
     			end
			else
			begin
//				$write("\n############[%d]: %d ", i, expect_cells[i].iexpect);
			end
//		$display;	
  		$display("@%0t: %m so far %0d expected cells, %0d actual cells received. Errors: %0d", $time, iexpect, iactual, nErrors);
	end
endtask: get_input_data

task scoreboard::get_output_data(uvm_tlm_analysis_fifo #(NNI_cell) fifo, int portn, uvm_phase phase);
	NNI_cell tx;
	ATMCellType Pkt;
	int i;
	int match_idx;
	bit found;

	forever begin
		bit found = 0;
		fifo.get(tx);
		tx.pack(Pkt);

		if (expect_cells[portn].q.size() == 0) begin
			$display("@%0t: ************ ERROR: %m cell not found because scoreboard for TX%0d empty", $time, portn);
//			tx.display("Not Found: ");
			nErrors++;
			continue;
		end
		expect_cells[portn].iactual++;
		iactual++;
		foreach (expect_cells[portn].q[i]) begin
			if (expect_cells[portn].q[i].compare(tx)) begin

				wrapper_cell wc = wrapper_cell::type_id::create("w");
				tx.display($sformatf("scoreboard pt %d collected nni_cell: ",portn));
				expect_cells[portn].q.delete(i);
				expect_cells[portn].iexpect--;


				wc._portn = portn;
				wc._nni_cell = tx;
				wc._io_type = wrapper_cell::OUTPUT_MONITOR;
				cov_ap.write(wc);
/*
				$write("############ SCOREBOARD EXPECT: ",iexpect);$display;
				for (int i=0; i<`RxPorts; i++)		
					if (i == portn)
						$write("\n############[%d]: %d --", i, expect_cells[i].iexpect);
					else
						$write("\n############[%d]: %d", i, expect_cells[i].iexpect);
					$display;	//*/
				found=1;
			end
		end
  		$display("@%0t: %m so far %0d expected cells, %0d actual cells received. Errors: %0d", $time, iexpect, iactual, nErrors);
		if (found)
			continue;
		$write("@%0t: ERROR: %m cell not found. portn: %d", $time, portn);
		foreach (Pkt.Mem[i]) $write("%x ", Pkt.Mem[i]); $display;
		nErrors++;
		error_cells.push_back(tx);
		// drop one objection to indicate that a packet was received. one step closer to terminate the simulation 
		phase.drop_objection(this);
	end
	// write
endtask : get_output_data

function void scoreboard::write(UNI_cell pkt);
	pkt.print();
endfunction : write

function void scoreboard::extract_phase( uvm_phase phase );
super.extract_phase(phase);
   $display("@%0t: %m %0d expected cells, %0d actual cells received", $time, iexpect, iactual);

   // Look for leftover cells
   foreach (expect_cells[i]) begin
      if (expect_cells[i].q.size()) begin
	 $display("@%0t: %m cells remaining in Tx[%0d] scoreboard at end of test", $time, i);
	 this.display("Unclaimed: ");
	 nErrors++;
      end
   end
endfunction : extract_phase

function void scoreboard::display(string prefix);
	$display("@%0t: %m so far %0d expected cells, %0d actual cells received", $time, iexpect, iactual);
	foreach (expect_cells[i]) begin
		$display("Tx[%0d]: exp=%0d, act=%0d", i, expect_cells[i].iexpect, expect_cells[i].iactual);
		foreach (expect_cells[i].q[j])
			expect_cells[i].q[j].display($sformatf("%sScoreboard: Tx%0d: ", prefix, i));
	end
	$display("---- ERROR CELLS!");
	foreach(error_cells[i])
		error_cells[i].display(" ERROR CELL: ");
endfunction : display


`endif // SCOREBOARD__SV