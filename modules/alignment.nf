/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow merge_consensus {
    take:
        grouped_bam

    main:

        MergeBamFiles(grouped_bam)
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
            -k15 -w5 -m20 -n3 \\
            $reference \\
            $fq > ${file_id}.sam
        """
}

process MergeBamFiles {
    publishDir { "${params.output_dir}/${sample_id}/consensus_alignments" }, mode: 'copy'
    container params.containers.samtools
    cpus 1
    memory 2.GB
    errorStrategy { task.exitStatus in [137, 140] ? 'retry' : 'finish' }
    maxRetries 3

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

process FilterR1Alignments {
    container params.containers.samtools
    cpus 1
    memory 1.GB

    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.filtered.bam"), path("${file_id}.filtered.bam.bai")

    script:
        """
        samtools view -b -f 64 -F 3844 $bam > ${file_id}.filtered.bam
        samtools index ${file_id}.filtered.bam
        """
}

process FilterBidirectionalAlignments {
    container params.containers.alnutils
    cpus 1
    memory 1.GB

    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.filtered.bam"), path("${file_id}.filtered.bai")

    script:
        """
        samtools view -b -F 2304 ${bam} > ${file_id}.filtered.bam
        samtools index ${file_id}.filtered.bam ${file_id}.filtered.bai
        """
}

process PosSortIndexAlignments {
    container params.containers.samtools
    cpus 1
    memory 100.MB

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.bam"), path("${file_id}.bam.bai") 

    script:
        """
        samtools sort -o ${file_id}.bam $sam
        samtools index ${file_id}.bam
        """
}

process NameSortAlignments {
    publishDir { "${params.output_dir}/${sample_id}/concatemer_alignments" }, mode: 'copy'
    container params.containers.samtools
    cpus 1
    memory 1.GB

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.bam")

    script:
        """
        samtools sort -n -o ${file_id}.bam $sam
        """
}
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/