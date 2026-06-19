include { PosSortIndexAlignments } from './common'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow align_consensus {
    take:
        consensus_reads
        reference
        regions
        mode

    main:
        Minimap2Align(consensus_reads, reference, mode)
        PosSortIndexAlignments(Minimap2Align.out)
        aligned_consensus_bam = PosSortIndexAlignments.out

        depth_table = GetAmpliconDepth(aligned_consensus_bam, regions)
        on_target_rate = GetOnTargetRate(aligned_consensus_bam, regions)

    emit:
        aligned_consensus_bam
        depth_table
        on_target_rate
}


workflow merge_consensus {
    take:
        annotated_bam_files

    main:
        MergeBamFiles(annotated_bam_files)
        merged_bam = MergeBamFiles.out

    emit:
        merged_bam
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process Minimap2Align {
    container params.containers.minimap2
    cpus 4
    memory 15.GB

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

process MergeBamFiles {
    publishDir { "${params.output_dir}/${sample_id}/consensus_alignments" }, mode: 'copy'
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

process GetOnTargetRate {
    container params.containers.alnutils
    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)
        path(bed)

    output:
        tuple val(sample_id), val(file_id), path("${sample_id}_on_target_rate.yml")

    script:
        """
        get_on_target_rate.sh ${bam} ${bed} ${sample_id}_on_target_rate.yml
        """
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