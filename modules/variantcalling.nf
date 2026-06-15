/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow call_variants {
    take:
        reads_aligned
        reference
        regions

    main:
        CallVariantsLofreq(reads_aligned, reference, regions)
        AnnotateVariants(CallVariantsLofreq.out)
        WriteVariantTable(AnnotateVariants.out)
    emit:
        variants = AnnotateVariants.out
        variant_table = WriteVariantTable.out
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process CallVariantsLofreq {
    // publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'

    container params.containers.lofreq
    memory 20.GB
    cpus 8

    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)
        tuple path(reference), val(reference_idx)
        path(bed)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.vcf")

    script:
        """
        lofreq faidx ${reference}

        lofreq call-parallel \
            --pp-threads ${task.cpus} \
            --call-indels \
            -m 20 -d 100000 \
            -f ${reference} \
            -l ${bed} \
            -o ${file_id}.vcf \
            ${bam}
        """
}

process AnnotateVariants {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    
    container params.containers.alnutils
    memory 4.GB
    cpus 2
    maxForks 1

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.annotated.vcf")

    script:
        """
        annotate_vcf.py ${vcf} ${file_id}.annotated.vcf
        """
}

process WriteVariantTable {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    
    container params.containers.alnutils
    memory 4.GB
    cpus 2

    input:
    tuple val(sample_id), val(file_id), path(vcf_file)

    output:
    tuple val(sample_id), path("${vcf_file.simpleName}.tsv"), path("${vcf_file.simpleName}.json")

    script:
    """
    write_variants_table.py ${vcf_file} ${vcf_file.simpleName}.tsv ${vcf_file.simpleName}.json
    """
}

    // write_variants_table.py ${vcf_file} ${vcf_file.simpleName}_table.json --tab-name 'Variant table' --priority-limit ${params.priority_limit} \
    // 2> >(tee -a error.txt >&2) || catch_plotting_errors.sh error.txt ${vcf_file.simpleName}_table.json

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/