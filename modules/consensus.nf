include { NameSortAlignments; PosSortIndexAlignments } from './common'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow generate_consensus {
    take:
        read_fastq
        reference

    main:
        Minimap2AlignConcatemers(read_fastq, reference)
        NameSortAlignments(Minimap2AlignConcatemers.out)
        // FilterAlignments(PosSortIndexAlignments.out)
        CyseqConsensus(NameSortAlignments.out, reference)
        BamToFastq(CyseqConsensus.out.map { it -> tuple(it[0], it[1], it[2]) })

    emit:
        consensus_fastq = BamToFastq.out
        consensus_folder = CyseqConsensus.out.map { it -> tuple(it[0], it[1], it[3]) }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process BamToFastq {
    container params.containers.samtools
    cpus 4
    memory 5.GB

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.fastq")

    script:
        """
        samtools fastq -@ ${task.cpus} $sam > ${file_id}.fastq
        """
}

process Minimap2AlignConcatemers {
    container params.containers.minimap2
    cpus 4
    memory 15.GB

    input:
        tuple val(sample_id), val(file_id), path(fq)
        tuple path(reference), val(reference_idx)
    
    output:
        tuple val(sample_id), val(file_id), path("${file_id}.sam") 

    script:
        """
        minimap2 -ax map-ont \\
          -t ${task.cpus} \\
          $reference \\
          $fq > ${file_id}.sam
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

process CyseqConsensus {
    cpus 8 // cpus = n + 4
    memory 20.GB
    
    // container params.containers.cyseqtools

    input:
        tuple val(sample_id), val(file_id), path(bam)
        tuple path(reference), val(reference_idx)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}_consensus/consensus.sam"), path("${file_id}_consensus")

    script:
        """
        cyseqtools consensus gw \\
            -n 4 \\
            -i $bam \\
            -r $reference \\
            -o ${file_id}_consensus
        """
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/