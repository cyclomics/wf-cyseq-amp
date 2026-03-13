/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process BuildReportData {
    container params.containers.alnutils
    publishDir "${params.output_dir}/report", mode: 'copy'

    input:
        path(counts_json)

    output:
        path("report_data.json"), emit: report_json
        path("report.html"), emit: report_html

    script:
    """
    build_report_data.py \
        --counts_json ${counts_json} \
        --template ${projectDir}/assets/report.html \
        --output report.html
    """
}

process FinalizeReport {
    container params.containers.alnutils
    publishDir "${params.output_dir}/report", mode: 'copy'

    input:
        path(report_html)
        path(report_json)

    output:
        path("report.html")

    script:
    """
    finalize_report.py \
        --html ${report_html} \
        --json ${report_json} \
        --output report.html
    """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/