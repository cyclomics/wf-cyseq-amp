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
    CountNumberOfReads;
    GetAmpliconDepth;
    } from './modules/common'
include { generate_cyseq_consensus } from './modules/consensus'
include {
    align_consensus_reads;
    merge_consensus_alignments;
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
    ingress_fastq_files(read_pattern, stop_pattern)
    raw_fastq = ingress_fastq_files.out.read_fastq

    // 1. Consensus
    generate_cyseq_consensus(raw_fastq, ch_reference)
    consensus_fastq = generate_cyseq_consensus.out.consensus_fastq
    consensus_folder = generate_cyseq_consensus.out.consensus_folder

    // 2. Alignment
    // samtools fastq to transform bam to sam, then minimap2
    align_consensus_reads(consensus_fastq, ch_reference, ch_regions, minimap2_mode)
    aligned_consensus_bam = align_consensus_reads.out.aligned_consensus_bam
    depth_table = align_consensus_reads.out.depth_table

    // REPORT: Live
    report_live(
        consensus_folder,
        depth_table,
    )

    // We require that all previous processes finish before continuing analysis.
    // groupTuple() controls this behaviour, since it collects all upstream channels.
    // 3. Merge all alignments
    grouped_aligned_consensus_bam = aligned_consensus_bam
            .groupTuple(by: 0)
            .map { it -> tuple(it[0], it[1], it[2]) }

    merge_consensus_alignments(grouped_aligned_consensus_bam)
    merged_bam = merge_consensus_alignments.out.merged_bam
    
    // 4. Variant calling
    merged_bam.view()
    ch_regions.view()
    call_variants(merged_bam, ch_regions, ch_reference)

    // REPORT: Final
    FinalizeReport(
        report_live.out.realtime_report.last().combine(
            call_variants.out.variant_table, by: 0
        )
    )
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
