/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow report_live {
    take:
        consensus_folder // [sample_id, file_id, consensus_metrics_folder]
        depth_table      // [sample_id, file_id, depth_yml] or channel.empty()

    main:
        // Accumulate consensus metrics
        running_consensus = consensus_folder
            .map { sample_id, file_id, consensus_metrics_folder ->
                tuple(sample_id, file_id, consensus_metrics_folder, consensusMetricsFolder(sample_id))
            }
            | UpdateRunningConsensusMetrics
            | map { sample_id, file_id, _dir, cards, plots ->
                tuple(sample_id, file_id, cards, plots)
            }


        // Accumulate amplicon depth
        running_depth = depth_table
            .map { sample_id, file_id, depth_yml ->
                tuple(sample_id, file_id, depth_yml, ampDepthYml(sample_id))
            }
            | UpdateRunningDepth
            | map { sample_id, file_id, _file ->
                tuple(sample_id, file_id, ampDepthYml(sample_id))
            }

        // Emit eagerly as soon as a matching pair is available
        // This is very important to make sure it emits real-time
        paired = running_depth
            .combine(running_consensus, by: [0, 1])


        ReportRealtime(paired)
        realtime_report = ReportRealtime.out.realtime_report

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

process UpdateRunningConsensusMetrics {
    container params.containers.cyseqtools
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(metrics_folder), path(published_folder)

    output:
        tuple val(sample_id), val(file_id), path(".consensus_metrics"), path("cards/cards.yaml"), path("plots/*.yaml")

    script:
        """
        mv $published_folder .prev_consensus_metrics
        sum_consensus_metrics.py \
            --metrics_folder $metrics_folder \
            --published_folder $published_folder
        """
}

process ReportRealtime {
    container params.containers.alnutils
    publishDir "${params.output_dir}", mode: 'copy'

    input:
        tuple val(sample_id), val(file_id), path(depth_yml), path(cards_yml), path(consensus_yml)

    output:
        tuple val(sample_id), path("report_${sample_id}.html"), path("report_${sample_id}.json"), emit: realtime_report

    script:
        def amplicon_arg = (depth_yml.name != 'null') ? "--amplicon_depth_yml ${depth_yml}" : ''
        """
        report_realtime.py \
            --template ${params.report_template} \
            --output_html report_${sample_id}.html \
            --output_json report_${sample_id}.json
        """
}

process FinalizeReport {
    container params.containers.alnutils
    publishDir "${params.output_dir}", mode: 'copy'

    input:
        tuple val(sample_id), path(report_html), path(report_json), path(variant_table)

    output:
        path("report_${sample_id}.html")

    script:
        """
        finalize_report.py \
            --html ${report_html} \
            --json ${report_json} ${variant_table} \
            --output report_${sample_id}.html
        """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

def reportsDir(sample_id) {
    "${params.output_dir}/${sample_id}/report"
}

def rawReadsYml(sample_id) {
    file("${reportsDir(sample_id)}/counts/number_of_reads_running.yml")
}

def ampDepthYml(sample_id) {
    file("${reportsDir(sample_id)}/depth/amplicon_depth_running.yml")
}

def consensusMetricsFolder(sample_id) {
    files("${reportsDir(sample_id)}/.consensus_metrics")
}