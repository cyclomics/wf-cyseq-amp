/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow report_live {
    take:
        consensus_folder // [sample_id, file_id, read_metrics_folder]
        depth_table      // [sample_id, file_id, depth_yml]
        on_target_rate    // [sample_id, file_id, on_target_rate_yml]

    main:
        // Accumulate read metrics
        live_read_metrics = consensus_folder
            .map { sample_id, file_id, read_metrics_folder ->
                tuple(sample_id, file_id, read_metrics_folder, consensusMetricsFolder(sample_id))
            }
            | StreamReadMetrics
            | map { sample_id, file_id, _dir, cards, plots ->
                tuple(sample_id, file_id, cards, plots)
            }


        // Accumulate amplicon depth
        live_depth = depth_table
            .map { sample_id, file_id, depth_yml ->
                tuple(sample_id, file_id, depth_yml, ampDepthYml(sample_id))
            }
            | StreamDepth
            | map { sample_id, file_id, _file ->
                tuple(sample_id, file_id, ampDepthYml(sample_id))
            }
        
        // Accumulate on-target rate
        live_on_target = on_target_rate
            .map { sample_id, file_id, on_target_rate_yml ->
                tuple(sample_id, file_id, on_target_rate_yml, onTargetRateYml(sample_id))
            }
            | StreamOnTargetRate
            | map { sample_id, file_id, _file ->
                tuple(sample_id, file_id, onTargetRateYml(sample_id))
            }

        // Emit eagerly as soon as matching streams are available
        paired = live_depth
            .combine(live_on_target, by: [0, 1])
            .combine(live_read_metrics, by: [0, 1])


        ReportStreamData(paired)
        live_report = ReportStreamData.out.report

    emit:
        live_report
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process StreamDepth {
    container params.containers.alnutils
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report/depth" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(depth_yml), path(published_file)

    output:
        tuple val(sample_id), val(file_id), path("amplicon_depth_live.yml")

    script:
        def target_depth_arg = params.target_depth != null ? "--target_depth ${params.target_depth}" : ''
        """
        sum_depth.py \
            --depth_yml "${depth_yml}" \
            --published_file "${published_file}" \
            $target_depth_arg
        """
}

process StreamOnTargetRate {
    container params.containers.alnutils
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report/depth" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(on_target_rate_yml), path(published_file)

    output:
        tuple val(sample_id), val(file_id), path("on_target_rate_live.yml")

    script:
        """
        sum_on_target_rate.sh \
            ${on_target_rate_yml} \
            ${published_file} \
            on_target_rate_live.yml
        """
}

process StreamReadMetrics {
    container params.containers.cyseqtools
    maxForks 1
    publishDir { "${params.output_dir}/${sample_id}/report" }, mode: 'copy', overwrite: true

    input:
        tuple val(sample_id), val(file_id), path(metrics_folder), path(published_folder)

    output:
        tuple val(sample_id), val(file_id), path(".read_metrics"), path("cards/cards.yaml"), path("plots/*.yaml")

    script:
        """
        mv $published_folder .prev_read_metrics
        sum_read_metrics.py \
            --metrics_folder $metrics_folder \
            --published_folder $published_folder
        """
}

process ReportStreamData {
    container params.containers.alnutils
    maxForks 1
    publishDir "${params.output_dir}", mode: 'copy'

    input:
        tuple val(sample_id), val(file_id),
              path(depth_yml),
              path(on_target_rate_yml),
              path(consensus_cards_yml), path(consensus_yml)

    output:
        tuple val(sample_id), path("report_${sample_id}.html"), path("report_${sample_id}.json"), emit: report

    script:
        """
        report_live.py \
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

def ampDepthYml(sample_id) {
    file("${reportsDir(sample_id)}/depth/amplicon_depth_live.yml")
}

def onTargetRateYml(sample_id) {
    file("${reportsDir(sample_id)}/depth/on_target_rate_live.yml")
}

def consensusMetricsFolder(sample_id) {
    files("${reportsDir(sample_id)}/.read_metrics")
}