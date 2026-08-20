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
        ch_variants = ReformatVcf.out

        DownloadSnpEffDb(params.reference)
        ch_snpeff_cache = DownloadSnpEffDb.out.cache.ifEmpty(null)

        ch_variants
            .combine(ch_snpeff_cache
                .map { it -> it ? 'available' : 'unavailable' }
                )
            .branch { sample_id, file_id, vcf, status ->
                annotate: status == 'available'
                    return [sample_id, file_id, vcf]
                passthrough: true
                    return [sample_id, file_id, vcf]
            }
            .set { ch_branched }

        AnnotateSnpEff(ch_branched.annotate, ch_snpeff_cache)
        CopyVcf(ch_branched.passthrough)
        ch_annotated = AnnotateSnpEff.out.mix(CopyVcf.out)

        WriteVariantTable(ch_annotated)

    emit:
        variants = ch_annotated
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
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy'
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

        awk 'NR > 1' $bed > bed_no_header.bed

        lofreq call-parallel \
            --pp-threads ${task.cpus} \
            --call-indels \
            -m 20 -d 100000000 \
            -f ${reference} \
            -l bed_no_header.bed \
            -o ${file_id}.vcf \
            ${bam}
        """
}

process FilterVcf {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy', pattern: "*.vcf"
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
        --af-min 0.00001 \
        -i ${vcf} \
        -o ${file_id}.filtered.vcf 
        """
}

process ReformatVcf {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy', pattern: "*.vcf"
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

process DownloadSnpEffDb {
    // storeDir "${params.snpeff_cache_dir}/${db_name}"
    storeDir "${workDir}/cache/${db_name}"
    container params.containers.snpeff
    cpus 1
    memory 4.GB
    errorStrategy 'ignore'

    input:
    val db_name

    output:
    path "snpeff", emit: cache

    script:
    """
    snpEff download -dataDir \${PWD}/snpeff ${db_name}
    """
}

process AnnotateSnpEff {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy', pattern: "*.vcf"
    container params.containers.snpeff
    cpus 1
    memory 10.GB

    input:
    tuple val(sample_id), val(file_id), path(vcf)
    path snpeff_cache

    output:
    tuple val(sample_id), val(file_id), path("${file_id}.ann.vcf")

    script:
    """
    snpEff ann -v \
        -dataDir \${PWD}/${snpeff_cache} \
        ${params.reference} \
        ${vcf} > ${file_id}.ann.vcf
    """
}

process CopyVcf {
    publishDir { "${params.output_dir}/${sample_id}/variants" }, mode: 'copy', pattern: "*.vcf"

    input:
    tuple val(sample_id), val(file_id), path(vcf)

    output:
    tuple val(sample_id), val(file_id), path("${file_id}.ann.vcf")

    script:
    """
    cp ${vcf} ${file_id}.ann.vcf
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