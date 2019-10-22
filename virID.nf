#!/usr/bin/env nextflow

nextflow.preview.dsl=2

// Log file must be set here to access laucnhDir information
params.log_file = "${workflow.launchDir}/${params.out_dir}/reports/virID.log"

//============================================================================//
// Set up modules
//============================================================================//
include './bin/modules/process_read_pairs' params(params)

include './bin/modules/spades_assembly' params(params)

include './bin/modules/diamond'  params(params)

include blast_to_LCA as convert_diamond from './bin/modules/blast_to_LCA' params(
  LCA_top_percent: params.LCA_top_percent,
  out_dir: params.out_dir,
  column_names: params.diamond_readable_colnames,
  source: 'diamond',
  taxid_blacklist: params.taxid_blacklist,
  within_percent_of_top_score: params.within_percent_of_top_score = "1",
  taxonomy_column: params.taxonomy_column,
  score_column:params.score_column
  )

include './bin/modules/blast' params(params)

include blast_to_LCA as convert_blast from './bin/modules/blast_to_LCA' params(
  LCA_top_percent: params.LCA_top_percent,
  out_dir: params.out_dir,
  column_names: params.blast_readable_colnames,
  source: 'blast',
  taxid_blacklist: params.taxid_blacklist
  )

include blast as blast_contaminant from './bin/modules/blast' params(
  blast_database: params.blast_contaminant_database,
  blast_evalue: params.blast_contaminant_evalue,
  blast_outfmt: params.blast_contaminant_outfmt,
  blast_log_file: params.blast_contaminant_log_file,
  blast_type: params.blast_contaminant_type,
  blast_max_hsphs: params.blast_contaminant_max_hsphs,
  blast_max_targets: params.blast_contaminant_max_targets,
  out_dir: "$params.out_dir/contaminant",
  log_file: params.log_file
  )

include './bin/modules/bwa_mem' params(params)

include './bin/modules/generate_output' params(params)

//============================================================================//
// Defining functions
//============================================================================//
def sampleID_set_from_infile(input) {
  // The purpose of this function is to take an input list of file paths and
  // to return a channel of sets of structure basename:file_path.
  sample_set = []
  for (String item : file(input)) {
    file = file(item)
    name = file.baseName
    sample_set.add([name, file])
  }
  ch = Channel.from(tuple(sample_set))
  return ch
}

//============================================================================//
// Read input data
//============================================================================//
input_ch = sampleID_set_from_infile(params.reads)

//============================================================================//
// Define workflows
//============================================================================//
workflow assembly {

  // Generate contigs
  process_read_pairs(input_ch) \
    | spades_assembly
    .filter{ it[1].size() > 0 }
    .set{ contigs }

  // Map reads back to assembly
  contigs
    .join(process_read_pairs.out) \
    | bwa_mem_contigs

  // DIAMOND processing
  diamond(contigs)
    .filter{ it[1].size() > 0 } \
    | convert_diamond

  // BLAST Processing
  blast(contigs)
    .filter{ it[1].size()>0 } \
    | convert_blast

  // Assignment against contaminant database
  blast_contaminant(contigs)

  // Merge channels and generate output
  convert_blast.out
    .join(convert_diamond.out)
    .join(contigs)
    .join(bwa_mem_contigs.out)
    .join(blast_contaminant.out) \
    | generate_output
}

//============================================================================//
// Call workflows
//============================================================================//
if ( params.assembly_pipeline == "T" ) {
  assembly
}
//if ( params.reads_pipeline == "T" ) {
//
//}
if( (params.assembly_pipeline == "F") && (params.reads_pipeline == "F") ) {
  error "One or both params.assembly_pipeline and params.reads_pipeline must \
  be set to T."
}

// processed_reads_ch.subscribe{ println it }
