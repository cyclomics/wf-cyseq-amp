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
include {
    FilterShortReads;
    IndexReference;
    FindRegionsOfInterest;
    CountNumberOfReads;
    UpdateTotalReads;
    } from './modules/common'
include { generate_cycas_consensus } from './modules/consensus'
include { align_consensus_reads } from './modules/alignment'
include { call_variants } from './modules/variantcalling'
include { BuildReportData; FinalizeReport } from './modules/report'

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

    def read_pattern = params.input_dir.endsWith("/")
            ? "${params.input_dir}${params.read_pattern}"
            : "${params.input_dir}/${params.read_pattern}"
        
    def stop_pattern = params.input_dir.endsWith("/")
        ? "${params.input_dir}${params.stop_pattern}"
        : "${params.input_dir}/${params.stop_pattern}"

    def ch_reference = IndexReference(channel.fromPath(params.reference)).collect()
    def minimap2_mode = params.minimap2.mode

    if (params.regions != "auto") {
        ch_regions = channel.value(file(params.regions))
    } else {
        log.info "Regions of interest will be detected automatically"
        ch_regions = channel.value("auto")
    }

    // Start ingress workflow
    ingress_fastq_files(read_pattern, stop_pattern)
    raw_fastq = ingress_fastq_files.out.read_fastq

    raw_fastq_json = CountNumberOfReads(raw_fastq, 'raw')

    total_reads = UpdateTotalReads(raw_fastq_json, file("${params.output_dir}/report/counts/number_of_reads_running.json"))


    // 1. Filter & QC
    FilterShortReads(raw_fastq)

    // 2. Consensus
    generate_cycas_consensus(FilterShortReads.out, ch_reference)
    consensus_fastq = generate_cycas_consensus.out.fastq
    consensus_json = generate_cycas_consensus.out.json

    // 3. Alignment
    align_consensus_reads(consensus_fastq, consensus_json, ch_reference, minimap2_mode)

    // 4. Variant calling
    regions = FindRegionsOfInterest(align_consensus_reads.out, ch_regions)
    call_variants(align_consensus_reads.out, regions, ch_reference)


    report_files = BuildReportData(total_reads)

    FinalizeReport(
        report_files.report_html.last(),
        report_files.report_json.last()
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
