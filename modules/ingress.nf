/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow ingress_fastq_files {
    take:
        input_dir

    main:

        def RUN_UID = generateUid( (('A'..'Z')+('a'..'z')+('0'..'9')).join(), 7 )

        def exclude_list = ['fastq_fail', 'fail']
        def invalid_parents = ['fastq', 'pass', 'fastq_pass', 'fastq_fail', 'fail', 'home']
        def BARCODE_PATTERN = params.barcode_pattern
        def RUN_FOLDER_PATTERN = params.run_folder_pattern

        def READ_PATTERN = input_dir.endsWith("/")
            ? "${input_dir}${params.read_pattern}"
            : "${input_dir}/${params.read_pattern}"
        
        def STOP_PATTERN = input_dir.endsWith("/")
            ? "${input_dir}${params.stop_pattern}"
            : "${input_dir}/${params.stop_pattern}"

        log.info "Looking for FASTQ files with pattern: ${READ_PATTERN}"
        log.info "Stopping when files matching pattern appear: ${STOP_PATTERN}"

        // -------------------------------------------------------------------
        // Initial STOP file
        initial_stop_files = channel.fromPath(STOP_PATTERN).ifEmpty('empty')
            .map {it -> it != 'empty' ? it.simpleName : "empty" }
        
        InitiateRealtimeIngress(initial_stop_files)
        stop_file_found = InitiateRealtimeIngress.out.stop

        // -------------------------------------------------------------------
        // Real-time STOP files
        rt_stop_files = channel.watchPath(STOP_PATTERN, 'create,modify').until{  stop_file_found }
        
        CheckRealtimeIngress(rt_stop_files.last(), stop_file_found)
        stop_file_found = CheckRealtimeIngress.out.stop
        stop_files = CheckRealtimeIngress.out.stop_files

        // -------------------------------------------------------------------
        // Existing FASTQ files
        initial_fastq_files = params.process_existing_files ?
            channel.fromPath(READ_PATTERN, checkIfExists: true) :
            channel.empty()

        initial_fastq_files = initial_fastq_files
            .map { it -> [it.Parent.simpleName, it.simpleName, it] }
            .filter { x -> x[1] != "DONE" }

        // -------------------------------------------------------------------
        // Real-time FASTQ files (stop when DONE appears)
        rt_fastq_files = channel.watchPath(READ_PATTERN, 'create,modify')
            .until { file -> file.name ==~ 'DONE.*\\.fastq.gz' }
            .map { it -> [it.parent.simpleName, it.simpleName, it] }

        // -------------------------------------------------------------------
        // Merge channels and add sample ID tagging
        read_fastq = initial_fastq_files.concat(rt_fastq_files)
            .map { meta ->
                def (barcode, sample_id) = getValidParent(meta[2].parent, invalid_parents, BARCODE_PATTERN, RUN_FOLDER_PATTERN)
                if (params.sample_id != "") sample_id = params.sample_id.toString()
                sample_id = sample_id.replaceAll("\\s+", "_") + "_${RUN_UID}"
                if (barcode != "") sample_id = "${sample_id}_${barcode}"
                tuple(sample_id, meta[1], meta[2])
            }

    emit:
        read_fastq = read_fastq
        stop_files = stop_files
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process InitiateRealtimeIngress {
    publishDir params.input_dir, pattern: "*DONE.*", mode: 'copy'

    input:
        val stop_file
    
    output:
        path "*DONE.*", optional: true, emit: stop_files
        val stop_file_created, emit: stop
    
    script:
        stop_file_created = false
        if (stop_file == 'empty') {
            stop_file_created = false
            log.warn('Initially there is no stop file')
            """
            ls
            """
        }
        else {
            log.warn("Stop file found, injecting pseudo files  to initiate exit in 3 seconds.")
            stop_file_created = true
            """
            sleep 3;
            echo \$(date) >> sequencing_summary_abc_DONE.txt
            echo \$(date) | gzip -c > DONE.fastq.gz
            """
        }

}

process CheckRealtimeIngress {
    publishDir params.input_dir, pattern: "*DONE.*", mode: 'copy'

    input:
        val stop_file
        val exit_started

    output:
        path "*DONE.*", optional: true, emit: stop_files
        val stop_file_created, emit: stop

    script:
        stop_file_created = true
        if (exit_started){
            log.warn("Stop condition met, but exit_started was already true.")
            """
            ls
            """
        }
        else {
            log.warn("Stop condition met.")
            """
            sleep 3;
            echo \$(date) >> sequencing_summary_abc_DONE.txt
            echo \$(date) | gzip -c > DONE.fastq.gz
            """
        }
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def generateUid(String alphabet, int n) {
    (1..n).collect { alphabet[ new java.util.Random().nextInt( alphabet.length() ) ] }.join()
}

def findValidParent(dir, invalidList, barcodePattern, runFolderPattern) {
    if (dir == null) {
        return null
    }
    
    def shouldSkip = invalidList.contains(dir.simpleName) || 
                     dir.simpleName ==~ barcodePattern || 
                     dir.simpleName ==~ runFolderPattern
    
    if (shouldSkip && dir.Parent != null) {
        return findValidParent(dir.Parent, invalidList, barcodePattern, runFolderPattern)
    }
    
    return dir
}

def getValidParent(dir, invalidList, barcodePattern, runFolderPattern) {
    def barcode = ""

    if (dir.simpleName ==~ barcodePattern) {
        barcode = dir.simpleName
    }

    def validParent = findValidParent(dir, invalidList, barcodePattern, runFolderPattern)
    
    return [barcode, validParent?.simpleName ?: ""]
}


