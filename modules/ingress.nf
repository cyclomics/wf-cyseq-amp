/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow ingress {
    take:
        read_pattern
        stop_pattern

    main:

        def RUN_UID = generateUid( (('A'..'Z')+('a'..'z')+('0'..'9')).join(), 7 )

        def exclude_list = ['fastq_fail', 'fail']
        def invalid_parents = ['fastq', 'pass', 'fastq_pass', 'fastq_fail', 'fail', 'home']
        def barcodePattern = asPattern(getMinKnowBarcodeFolderPattern())
        def runFolderPattern = asPattern(getMinKnowAutoRunFolderPattern())

        

        log.info "Looking for FASTQ files with pattern: ${read_pattern}"
        log.info "Stopping when files matching pattern appear: ${stop_pattern}"

        // -------------------------------------------------------------------
        // Initial STOP file
        initial_stop_files = channel.fromPath(stop_pattern)
            .ifEmpty('empty')
            .map {it -> it != 'empty' ? it.simpleName : "empty" }
        
        InitiateIngress(initial_stop_files)
        stop_file_found = InitiateIngress.out.stop

        // -------------------------------------------------------------------
        // Real-time STOP files
        rt_stop_files = channel.watchPath(stop_pattern, 'create,modify')
            .until{  stop_file_found }
        
        CheckIngress(rt_stop_files.last(), stop_file_found)
        stop_file_found = CheckIngress.out.stop
        stop_files = CheckIngress.out.stop_files

        // -------------------------------------------------------------------
        // Existing FASTQ files
        initial_fastq_files = params.process_existing_files ?
            channel.fromPath(read_pattern, checkIfExists: true) :
            channel.empty()

        initial_fastq_files = initial_fastq_files
            .map { file -> tuple(file.parent.simpleName, file.simpleName, file) }
            .filter { _parent_name, sample_name, _file -> sample_name != "DONE" }

        // -------------------------------------------------------------------
        // Real-time FASTQ files (stop when DONE appears)
        rt_fastq_files = channel.watchPath(read_pattern, 'create,modify')
            .until { file -> file.name ==~ 'DONE.*\\.fastq.gz' }
            .map { file -> tuple(file.parent.simpleName, file.simpleName, file) }

        // -------------------------------------------------------------------
        // Merge channels and add sample ID tagging
        read_fastq = initial_fastq_files
            .concat(rt_fastq_files)
            .map { _parent_name, file_name, file ->
            
                def (barcode, sample_id) = extractSampleInfo(
                    file.parent,
                    invalid_parents,
                    barcodePattern,
                    runFolderPattern
                    )

                sample_id = formatSampleId(sample_id, barcode, RUN_UID)
                tuple(sample_id, file_name, file)
            }
        
        // TODO: we shouldn't even parse those files to begin with
        if (params.include_fastq_fail == false) {
            read_fastq = read_fastq.filter { 
                _parent_name, _sample_name, file -> !(file.Parent.SimpleName in exclude_list || file.Parent?.Parent.SimpleName in exclude_list) 
            }
        }
        
        if (params.split_fastq_by_size == true) {
            log.info "Splitting FASTQ files into smaller chunks of size: ${params.split_size} bytes"

            ingested_fastq = SplitFastq(read_fastq)
                .flatMap { sample_id, file_id, file_list ->
                    if (file_list instanceof List) {
                        file_list.collect { file ->
                            def new_file_id = file.getBaseName()
                            return [sample_id, new_file_id, file]
                        }
                    } else {
                        def new_file_id = file_list.getBaseName()
                        return [[sample_id, new_file_id, file_list]]
                    }
                }
        } else {
            ingested_fastq = read_fastq
        }

    emit:
        ingested_fastq = ingested_fastq
        stop_files = stop_files
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process InitiateIngress {
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

process CheckIngress {
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

process SplitFastq {
    publishDir "${params.output_dir}/split", mode: 'copy'
    container params.containers.seqkit
    
    input:
        tuple val(sample_id), val(file_id), path(fastq)

    output:
        tuple val(sample_id), val(file_id), path("split/${file_id}_*.fastq.gz")

    script:
        """
        seqkit split -j ${task.cpus} -e .gz -s $params.max_fastq_size --by-size-prefix ${file_id}_ -O split $fastq
        """
}    

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def generateUid(String alphabet, int n) {
    // Generate a random UID of length n using the provided alphabet.
    (1..n).collect { alphabet[ new java.util.Random().nextInt( alphabet.length() ) ] }.join()
}

def asPattern(patternLike) {
    if (patternLike instanceof java.util.regex.Pattern) {
        return patternLike
    }
    return java.util.regex.Pattern.compile(patternLike.toString())
}

def getMinKnowBarcodeFolderPattern() {
    // Return the pattern for folder generated by MinKnow when doing barcode sequencing.
    // This is anonymous function is here to test its behavior in the getValidParent function, as we want to make sure that the barcode folders are correctly identified and ignored when looking for the sample ID.
    '^barcode\\d{2,3}$|unclassified'
}

def getMinKnowAutoRunFolderPattern() {
    // Return the pattern for folder generated by MinKnow for all sequence runs.
    '^\\d{8}_\\d{4}_.+'
}

def formatSampleId(String sample_id, String barcode, String run_uid) {
    // Format the sample ID by combining sample_id, barcode, and run_uid with optional param override
    // If params.sample_id is set, it overrides the sample_id
    // Replaces whitespace with underscores and combines components with underscores
    
    if (params.sample_name != "") {
        sample_id = params.sample_name.toString()
        sample_id = sample_id.replaceAll("\\s+", "_")
        sample_id = sample_id + "_" + run_uid

    } else if (sample_id != "") {
        sample_id = sample_id.replaceAll("\\s+", "_")
        sample_id = sample_id + "_" + run_uid

    } else {
        sample_id = run_uid
    }
    
    if (barcode != "") {
        sample_id = sample_id + "_" + barcode
    }
    
    return sample_id
}

def findValidParentDir(dir, invalidList, barcodePattern, runFolderPattern) {
    /* Recursively find a valid parent directory path that is not in the invalid list and does not match the barcode or run folder patterns.
    
    The valid parent is normally the sample ID given in MinKnow
    A valid parent directory is defined as one that:
    - Is not in the invalidList
    - Does not match the barcodePattern
    - Does not match the runFolderPattern


    dir: {String} the current directory to check
    invalidList: {List} a list of directory names to ignore
    barcodePattern: {Pattern} a regex pattern to identify barcode folders
    runFolderPattern: {Pattern} a regex pattern to identify run folders    
    
    Returns:
    - The valid parent directory path, or / if no valid parent is found.
    */
    def folder_name = dir.simpleName

    def invalidFolderName = invalidList.contains(folder_name) || 
                     folder_name ==~ barcodePattern || 
                     folder_name ==~ runFolderPattern
    
    // look one level up if current position is invalid, otherwise return current position
    if (invalidFolderName) {
        return findValidParentDir(dir.Parent, invalidList, barcodePattern, runFolderPattern)
    }
    return dir
}


def extractSampleInfo(dir, invalidList, barcodePattern, runFolderPattern) {
    /*
    get a sample and file id from a path

    dir: {String} the current directory to check
    invalidList: {List} a list of directory names to ignore
    barcodePattern: {Pattern} a regex pattern to identify barcode folders
    runFolderPattern: {Pattern} a regex pattern to identify run folders    
    
    Returns:
    sample_id
    file_id
    */
    
    def barcode = ""

    if (dir.simpleName ==~ barcodePattern) {
        barcode = dir.simpleName
    }

    def validParent = findValidParentDir(dir, invalidList, barcodePattern, runFolderPattern)

    return [barcode, validParent?.simpleName ?: ""]
}
