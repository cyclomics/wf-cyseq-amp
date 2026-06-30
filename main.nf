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
include { ingress } from './modules/ingress'
include {
    IndexReference;
    GetAmpliconDepth;
    } from './modules/common'
include { make_consensus } from './modules/consensus'
include {
    get_amplicon_metrics;
    merge_consensus;
    } from './modules/alignment'
include { call_variants } from './modules/variantcalling'
include {
    report_live;
    FinalizeReport
    } from './modules/report'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow {
    assert params.input_dir : "--input_dir cannot be empty. Please provide a folder containing input FASTQ files or containing a subfolder with input FASTQ files."
    assert params.reference : "--reference cannot be empty. Please provide a reference genome in FASTA format. Variant annotation is only compatible with GRCh38."
    assert params.regions   : "--regions cannot be empty. Please provide an input BED file with loci of interest."

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
    def ch_regions = channel.value(file(params.regions)).collect()

    // Start ingress workflow
    ingress(read_pattern, stop_pattern)
    raw_fastq = ingress.out.ingested_fastq

    // 1. Consensus
    make_consensus(raw_fastq, ch_reference)
    consensus_sam = make_consensus.out.consensus_sam
    consensus_folder = make_consensus.out.consensus_folder

    // 2. Alignment
    // samtools fastq to transform bam to sam, then minimap2
    get_amplicon_metrics(consensus_sam, ch_regions)
    aligned_consensus_bam = get_amplicon_metrics.out.aligned_consensus_bam
    depth_table = get_amplicon_metrics.out.depth_table
    on_target_rate = get_amplicon_metrics.out.on_target_rate

    // REPORT: Live
    report_live(
        consensus_folder,
        depth_table,
        on_target_rate
    )

    // We require that all previous processes finish before continuing analysis.
    // groupTuple() controls this behaviour, since it collects all upstream channels.
    // 3. Merge all alignments
    grouped_aligned_consensus_bam = aligned_consensus_bam
            .groupTuple(by: 0)
            .map { it -> tuple(it[0], it[1], it[2]) }

    merge_consensus(grouped_aligned_consensus_bam)
    merged_bam = merge_consensus.out.merged_bam
    
    // 4. Variant calling
    call_variants(merged_bam, ch_reference, ch_regions)

    // REPORT: Final
    FinalizeReport(
        report_live.out.live_report
            .groupTuple(by: 0)
            .map { sample_id, htmls, jsons -> tuple(sample_id, htmls[-1], jsons[-1]) }
            .combine(call_variants.out.variant_table, by: 0)
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
