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
        Minimap2Alignment(read_fastq, reference_genome)
        IndexWithId(Minimap2Alignment.out)
        FilterAlignments(IndexWithId.out)
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
process Minimap2Alignment {
    container params.containers.minimap2

    input:
        tuple val(sample_id), val(file_id), path(fq)
        path(reference_genome)
    
    output:
        tuple val(sample_id), val(file_id), path("${file_id}.bam") 

    script:
        """
        minimap2 -ax map-ont \\
          -t ${task.cpus} \\
          -m ${params.minimap2.min_chain_score} \\
          -n ${params.minimap2.min_chain_count} \\
          -s ${params.minimap2.min_peak_aln_score} \\
          $reference_genome \\
          $fq | \\ 
        samtools sort -o ${file_id}.bam -
        """
}

process IndexWithId {
    container params.containers.samtools

    input:
        tuple val(sample_id), val(file_id), path(bam)

    output:
        tuple val(sample_id), val(file_id), path(bam), path("*.bai") 

    script:
        """
        samtools index $bam
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