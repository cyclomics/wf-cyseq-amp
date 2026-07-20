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
        FilterAlignments(reads_aligned)
        CallVariantsLofreq(FilterAlignments.out, reference, regions)
        FilterVcf(CallVariantsLofreq.out)
        ReformatVcf(FilterVcf.out)
        AnnotateSnpEff(ReformatVcf.out)
        WriteVariantTable(AnnotateSnpEff.out)
    emit:
        variants = AnnotateSnpEff.out
        variant_table = WriteVariantTable.out.map { sample_id, _tsv, json -> tuple(sample_id, json) }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process FilterAlignments {
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

process CallVariantsLofreq {
    // publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    container params.containers.lofreq
    cpus 8
    memory 5.GB
    
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

process FilterVcf {
    container params.containers.lofreq
    maxForks 1
    cpus 1
    memory 200.MB

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.filtered.vcf")

    script:
        """
        lofreq filter \
        --af-min 0.001 \
        -i ${vcf} \
        -o ${file_id}.filtered.vcf 
        """
}

process ReformatVcf {
    container params.containers.alnutils
    maxForks 1
    cpus 1
    memory 200.MB

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.reformatted.vcf")

    script:
        """
        reformat_vcf.py lofreq ${vcf} ${file_id}.reformatted.vcf
        """
}

process AnnotateVariants {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    container params.containers.alnutils
    maxForks 1
    cpus 1
    memory 200.MB

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.annotated.vcf")

    script:
        """
        annotate_vcf.py ${vcf} ${file_id}.annotated.vcf
        """
}

process AnnotateSnpEff {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy', pattern: "*.vcf"
    container params.containers.snpeff
    cpus 1
    memory 8.GB

    input:
        tuple val(sample_id), val(file_id), path(vcf)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.ann.vcf")

    script:
        """
        snpEff download -dataDir \${PWD}/snpeff_data ${params.reference}
        snpEff ann -v -dataDir \${PWD}/snpeff_data ${params.reference} ${vcf} > ${file_id}.ann.vcf
        """
}

process WriteVariantTable {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
    container params.containers.alnutils
    cpus 1
    memory 50.MB

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