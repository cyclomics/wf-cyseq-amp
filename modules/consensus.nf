/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow generate_cycas_consensus {
    take:
        read_fastq
        reference_genome

    main:
        IndexReference(reference_genome)
        Minimap2Alignment(read_fastq, IndexReference.out)
        SortIndexAlignments(Minimap2Alignment.out)
        FilterAlignments(SortIndexAlignments.out)
        Cycas(FilterAlignments.out)

    emit:
        fastq = Cycas.out.map { it -> tuple(it[0], it[1], it[2]) }
        json = Cycas.out.map { it -> tuple(it[0], it[1], it[3]) }
        split_bam = Minimap2Alignment.out
        split_bam_filtered = FilterAlignments.out.map { it -> tuple(it[0], it[1], it[2]) }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process IndexReference{
    container params.containers.samtools
    
    input:
        path(reference)
    
    output:
        tuple path(reference), path("${reference}.fai")

    script:
        """
        samtools faidx $reference
        """
}

process Minimap2Alignment {
    container params.containers.minimap2
    cpus 4
    memory 20.GB

    input:
        tuple val(sample_id), val(file_id), path(fq)
        tuple path(reference), val(reference_idx)
    
    output:
        tuple val(sample_id), val(file_id), path("${file_id}.sam") 

    script:
        """
        minimap2 -ax map-ont \\
          -t ${task.cpus} \\
          -m ${params.minimap2.min_chain_score} \\
          -n ${params.minimap2.min_chain_count} \\
          -s ${params.minimap2.min_peak_aln_score} \\
          $reference \\
          $fq > ${file_id}.sam
        """
}

process SortIndexAlignments {
    container params.containers.samtools

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

process FilterAlignments {
    container params.containers.samtools
    
    input:
        tuple val(sample_id), val(file_id), path(bam_in), path(bai_in)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.filtered.bam"), path("${file_id}.filtered.bam.bai")

    script:
        """
        samtools view -b \\
          -F 256 \\
          --input-fmt-option 'filter=[NM]<50 && mapq >20' \\
          -o ${file_id}.filtered.bam \\
          $bam_in 
        samtools index ${file_id}.filtered.bam
        """
}

process Cycas {
    publishDir "${params.output_dir}/consensus", mode: 'copy'
    cpus 4
    memory 10.GB

    container params.containers.cycas

    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.consensus.fastq"), path("${file_id}.metadata.json")

    script:
        """
        python $params.cycas_location consensus \\
          --input-bam $bam \\
          --output-fastq ${file_id}.consensus.fastq \\
          --output-json ${file_id}.metadata.json \\
          --calibration-model ${params.calibration_model}
        """
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/