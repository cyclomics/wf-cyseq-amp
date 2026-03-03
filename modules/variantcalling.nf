/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow call_variants {
    take:
        reads_aligned
        positions
        reference

    main:
        CallVariantsLofreq(reference, reads_aligned.combine(positions, by: [0, 1]))
    emit:
        locations = CallVariantsLofreq.output
        variants = CallVariantsLofreq.output
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process CallVariantsLofreq {
    publishDir "${params.output_dir}/variants", mode: 'copy'

    container params.containers.lofreq
    memory 20.GB
    cpus 8

    input:
        tuple path(reference), val(reference_idx)
        tuple val(sample_id), val(file_id), path(bam), path(bai), path(bed)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.vcf")

    script:
        """
        lofreq faidx ${reference}

        BED_ARG=""
        if [ -s "${bed}" ]; then
            BED_ARG="-l ${bed}"
        fi

        lofreq call-parallel \
            --pp-threads ${task.cpus} \
            --call-indels \
            -m 20 \
            -a 1 -b 1 \
            -f ${reference} \
            \${BED_ARG} \
            -o ${file_id}.vcf \
            ${bam}
        """
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/