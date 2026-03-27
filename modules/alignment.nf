include { SortIndexAlignments } from './common'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow align_consensus_reads {
    take:
        consensus_reads_fastq
        consensus_reads_json
        reference
        mode
        regions

    main:
        Minimap2AlignConsensus(consensus_reads_fastq, reference, mode)
        SortIndexAlignments(Minimap2AlignConsensus.out)
        metadata_pairs = SortIndexAlignments.out.combine(consensus_reads_json, by: [0, 1])
        
        annotated_bam = AnnotateBamYTags(metadata_pairs)

        if (regions != 'auto') {
            depth_table = GetAmpliconDepth(annotated_bam, regions)
        } else {
            depth_table = channel.empty()
        }

    emit:
        annotated_bam
        depth_table
        
}


workflow merge_consensus_alignments {
    take:
        annotated_bam_files
        ch_regions

    main:
        MergeBamFiles(annotated_bam_files)
        merged_bam = MergeBamFiles.out
        regions = FindRegionsOfInterest(merged_bam, ch_regions)

    emit:
        merged_bam
        regions
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process Minimap2AlignConsensus {
    container params.containers.minimap2
    cpus 8
    memory 20.GB

    input:
        tuple val(sample_id), val(file_id), path(fq)
        tuple path(reference), val(reference_idx)
        val(mode)
    
    output:
        tuple val(sample_id), val(file_id), path("${file_id}.sam") 

    script:
        """
        minimap2 -ax ${mode} \\
            -t ${task.cpus} \\
            $reference \\
            $fq > ${file_id}.sam
        """
}

process AnnotateBamYTags {
    container params.containers.alnutils
    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai), path(json)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.annotated.bam"), path("${file_id}.annotated.bam.bai")

    script:
        """
        annotate_bam_y.py ${json} ${bam} ${file_id}.annotated.bam
        """
}

process MergeBamFiles {
    publishDir "${params.output_dir}/${sample_id}/consensus_alignments", mode: 'copy'
    container params.containers.samtools

    input:
        tuple val(sample_id), val(file_ids), path(bams_in)

    output:
        tuple val(sample_id), val(sample_id), path("${sample_id}.merged.bam"), path("${sample_id}.merged.bam.bai")
    
    script:
        """
        samtools merge -p -c -O bam ${sample_id}.merged.bam \$(find . -name '*.bam')
        samtools index ${sample_id}.merged.bam
        """
}

process FindRegionsOfInterest{
    container params.containers.alnutils
    
    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)
        val(regions)

    output:
        tuple val(sample_id), val(file_id), path("${sample_id}_roi.bed")

    script:
        if (regions == 'auto') {
            """
            samtools depth $bam \
             | awk '\$3>${params.roi_detection.min_depth}' \
             | awk '{print \$1"\t"\$2"\t"\$2 + 1}' \
             | bedtools merge -d ${params.roi_detection.max_distance} -i /dev/stdin \
             > ${sample_id}_roi.bed
            """
        } else {
            """
            cp $regions ${sample_id}_roi.bed
            """
        }
}

process GetAmpliconDepth {
    container params.containers.alnutils
    
    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)
        path(bed)

    output:
        tuple val(sample_id), val(file_id), path("${sample_id}_amplicon_depth.yml")

    script:
        """
        samtools depth -a -J -b $bed $bam > ${sample_id}_depth.tsv
        get_amplicon_depth.py ${sample_id}_depth.tsv $bed ${sample_id}_amplicon_depth.yml
        """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/