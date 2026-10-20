/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow report_live {
    take:
        consensus_folder // [sample_id, file_id, read_metrics_folder]

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

        ReportStreamData(live_read_metrics, channel.fromPath(params.report_template).collect())
        live_report = ReportStreamData.out.report

    emit:
        live_report
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process StreamReadMetrics {
    publishDir { "${params.output_dir}/${sample_id}/report" }, mode: 'copy', overwrite: true
    container params.containers.cyseqtools
    maxForks 1
    cpus 1
    memory 2.GB

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
    publishDir "${params.output_dir}", mode: 'copy'
    container params.containers.alnutils
    maxForks 1
    cpus 1
    memory 2.GB

    input:
        tuple val(sample_id), val(file_id),
              path(consensus_cards_yml), path(consensus_plots_yml)
        path report_template

    output:
        tuple val(sample_id), path("report_${sample_id}*.html"), path("report_${sample_id}.json"), emit: report

    script:
        def absoluteOutputDir = file(params.output_dir).toAbsolutePath()
        def epiFlag = params.epi2me_report ? "--epi2me_report" : ""
        """
        report_live.py \
            --template ${report_template} \
            --sample_id ${sample_id} \
            ${epiFlag} \
            --clean_dir "${absoluteOutputDir}"
        """
}

process FinalizeReport {
    publishDir "${params.output_dir}", mode: 'copy'
    container params.containers.alnutils
    cpus 1
    memory 4.GB

    input:
        tuple val(sample_id), path(report_html), path(report_json), path(variant_table)

    output:
        path("report_${sample_id}.html")

    script:
        def absoluteOutputDir = file(params.output_dir).toAbsolutePath()
        def epiFlag = params.epi2me_report ? "--epi2me_report" : ""
        """
        finalize_report.py \
            --html ${report_html} \
            --json ${report_json} ${variant_table} \
            --sample_id ${sample_id} \
            ${epiFlag} \
            --clean_dir "${absoluteOutputDir}"     
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