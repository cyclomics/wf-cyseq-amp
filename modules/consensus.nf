include { NameSortAlignments; PosSortIndexAlignments } from './common'
include { Minimap2Align } from './alignment'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow make_consensus {
    take:
        read_fastq
        reference

    main:
        Minimap2Align(read_fastq, reference, "map-ont")
        NameSortAlignments(Minimap2Align.out)
        CyseqConsensus(NameSortAlignments.out, reference)
        SamToFastq(CyseqConsensus.out.map { it -> tuple(it[0], it[1], it[2]) })

    emit:
        consensus_fastq = SamToFastq.out
        consensus_folder = CyseqConsensus.out.map { it -> tuple(it[0], it[1], it[3]) }
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process SamToFastq {
    container params.containers.samtools
    cpus 1
    memory 50.MB

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.fastq")

    script:
        """
        samtools fastq -@ ${task.cpus} $sam > ${file_id}.fastq
        """
}

process CyseqConsensus {
    cpus 8 // cpus = n + 4
    memory 20.GB
    
    container params.containers.cyseqtools

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