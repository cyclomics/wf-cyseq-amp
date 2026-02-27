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

    main:
        Minimap2AlignConsensus(consensus_reads_fastq, reference, mode)
        SortIndexAlignments(Minimap2AlignConsensus.out)
        metadata_pairs = SortIndexAlignments.out.combine(consensus_reads_json, by: [0, 1])
        
        AnnotateBamYTags(metadata_pairs)
        annotated_bam_files = AnnotateBamYTags.out
            .groupTuple(by: 0)
            .map { it -> tuple(it[0], it[1], it[2]) }
        
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
process Minimap2AlignConsensus {
    container params.containers.minimap2
    cpus 4
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


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/