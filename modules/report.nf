/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow report_realtime {
    take:
        raw_fastq_json   // [sample_id, file_id, reads_json]
        depth_table      // [sample_id, file_id, depth_yml] or channel.empty()

    main:
        // Accumulate raw read counts
        running_reads = raw_fastq_json.map { sample_id, file_id, reads_json ->
            tuple(
                sample_id,
                file_id,
                reads_json,
                file("${params.output_dir}/${sample_id}/report/counts/number_of_reads_running.yml")
            )
        } | UpdateRunningReads

        if (params.regions != 'auto') {
            // Accumulate amplicon depth
            running_depth = depth_table.map { sample_id, file_id, depth_yml ->
                tuple(
                    sample_id,
                    file_id,
                    depth_yml,
                    file("${params.output_dir}/${sample_id}/report/depth/amplicon_depth_running.yml")
                )
            } | UpdateRunningDepth
            // Emit eagerly as soon as a matching pair is available
            // This is very important to make sure it emits real-time
            paired = running_reads.combine(running_depth, by: [0, 1])
        } else {
            // If BED file is not provided, return null
            paired = running_reads.map { sample_id, file_id, counts_yml ->
                tuple(sample_id, file_id, counts_yml, file('/dev/null'))
            }
        }

        ReportRealtimeStats(paired)
        realtime_report = ReportRealtimeStats.out.realtime_report

    emit:
        realtime_report
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process UpdateRunningReads {
    container params.containers.alnutils
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report/counts" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(json_file), path(published_file)

    output:
        tuple val(sample_id), val(file_id), path("number_of_reads_running.yml")

    script:
        """
        sum_reads.py \
            --json_file "${json_file}" \
            --published_file "${published_file}"
        """
}

process UpdateRunningDepth {
    container params.containers.alnutils
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report/depth" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(depth_yml), path(published_file)

    output:
        tuple val(sample_id), val(file_id), path("amplicon_depth_running.yml")

    script:
        def target_depth_arg = params.target_depth != null ? "--target_depth ${params.target_depth}" : ''
        """
        sum_depth.py \
            --depth_yml "${depth_yml}" \
            --published_file "${published_file}" \
            $target_depth_arg
        """
}

process ReportRealtimeStats {
    container params.containers.alnutils
    publishDir "${params.output_dir}", mode: 'copy'

    input:
        tuple val(sample_id), val(file_id), path(counts_yml), path(depth_yml)

    output:
        tuple val(sample_id), path("report_${sample_id}.html"), path("report_${sample_id}.json"), emit: realtime_report

    script:
        def amplicon_arg = (depth_yml.name != 'null') ? "--amplicon_depth_yml ${depth_yml}" : ''
        """
        report_realtime_stats.py \
            --counts_yml ${counts_yml} \
            --template ${params.report_template} \
            --output_html report_${sample_id}.html \
            --output_json report_${sample_id}.json \
            --sample_id ${sample_id} \
            ${amplicon_arg}
        """
}

process FinalizeReport {
    container params.containers.alnutils
    publishDir "${params.output_dir}", mode: 'copy'

    input:
        tuple val(sample_id), path(report_html), path(report_json)

    output:
        path("report_${sample_id}.html")

    script:
        """
        finalize_report.py \
            --html ${report_html} \
            --json ${report_json} \
            --output report_${sample_id}.html
        """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/