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
        AnnotateVariants(CallVariantsLofreq.out)
        PasteVariantTable(AnnotateVariants.out)
    emit:
        variants = AnnotateVariants.out
        variant_table = PasteVariantTable.out
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process CallVariantsLofreq {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'

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
            -f ${reference} \
            \${BED_ARG} \
            -o ${file_id}.vcf \
            ${bam}
        """
}

process AnnotateVariants {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    
    container params.containers.alnutils
    memory 4.GB
    cpus 2

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.annotated.vcf")

    script:
        """
        annotate_vcf.py ${vcf} ${file_id}.annotated.vcf
        """
}

process PasteVariantTable {
    publishDir "${params.output_dir}/QC", mode: 'copy'
    label 'many_low_cpu_high_mem'

    input:
    tuple val(sample_id), val(file_id), path(vcf_file)

    output:
    tuple val(sample_id), path("${vcf_file.simpleName}_table.json")

    script:
    """
    write_variants_table.py ${vcf_file} ${vcf_file.simpleName}_table.json --priority-limit 89
    """
}

    // write_variants_table.py ${vcf_file} ${vcf_file.simpleName}_table.json --tab-name 'Variant table' --priority-limit ${params.priority_limit} \
    // 2> >(tee -a error.txt >&2) || catch_plotting_errors.sh error.txt ${vcf_file.simpleName}_table.json

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/