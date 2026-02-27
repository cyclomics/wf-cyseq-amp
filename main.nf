#!/usr/bin/env nextflow
/*
========================================================================================
    Workflow name
========================================================================================
    Github: https://github.com/cyclomics/wf-cyclomicsseq-amp
    Website: https://www.cyclomics.com/
----------------------------------------------------------------------------------------
*/

nextflow.preview.recursion = true

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / PROCESSES / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { ingress_fastq_files } from './modules/ingress'
include { FilterShortReads; IndexReference } from './modules/common'
include { generate_cycas_consensus } from './modules/consensus'
include { align_consensus_reads } from './modules/alignment'
// include { call_variants } from './modules/variants'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow {
    assert params.input_dir : "--input_dir cannot be empty!"
    assert params.reference : "--reference cannot be empty!"

    def allowed_modes = ["map-ont", "sr"]
    assert params.minimap2?.mode in allowed_modes :
        "--minimap2.mode must be one of: ${allowed_modes.join(', ')}"

    def INPUT_DIR = params.input_dir
    def ch_reference = IndexReference(channel.fromPath(params.reference))
    def minimap2_mode = params.minimap2.mode

    // Start ingress workflow
    ingress_fastq_files(INPUT_DIR)
    // ingress_fastq_files.out.view()

    // 1. Filter & QC
    FilterShortReads(ingress_fastq_files.out.read_fastq)
    // FilterShortReads.out.view()

    // 2. Consensus
    generate_cycas_consensus(FilterShortReads.out, ch_reference)
    consensus_fastq = generate_cycas_consensus.out.fastq
    consensus_json = generate_cycas_consensus.out.json
    // generate_cycas_consensus.out.view()

    // 3. Alignment
    align_consensus_reads(consensus_fastq, consensus_json, ch_reference, minimap2_mode)

    // 4. Variant calling
    // call_variants(align_consensus_reads.out, ch_reference)

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
