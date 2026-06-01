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
        def RUN_UID = generateUid((('A'..'Z') + ('a'..'z') + ('0'..'9')).join(), 7)

        def exclude_list = ['fastq_fail', 'fail']
        def invalid_parents = ['fastq', 'pass', 'fastq_pass', 'fastq_fail', 'fail', 'home']
        def barcodePattern = asPattern(getMinKnowBarcodeFolderPattern())
        def runFolderPattern = asPattern(getMinKnowAutoRunFolderPattern())

        log.info "Looking for FASTQ files with pattern: ${read_pattern}"
        log.info "Stopping when files matching pattern appear: ${stop_pattern}"

        // Resolve input dir to absolute
        def input_dir = file(params.input_dir).toAbsolutePath().toString()

        // Extract the stop file name pattern (glob -> regex)
        def stop_path_str = stop_pattern.toString()
        def stop_name_pattern = stop_path_str.split('/')[-1]
            .replace('.', '\\.')
            .replace('*', '.*')

        log.info "Watching: ${input_dir}"
        log.info "Stop filename regex: ${stop_name_pattern}"

        // Check if stop signal already exists
        def stop_already_exists = !file(stop_pattern).isEmpty()

        if (stop_already_exists) {
            log.info "Stop signal already present, processing existing files."

            // Just collect what's there
            read_fastq_raw = channel.fromPath(read_pattern)
                .filter { f -> !(f.parent.simpleName in exclude_list) }
                .map { f -> tuple(f.parent.simpleName, f.simpleName, f) }

        } else {
            log.info "No stop signal yet, starting real-time ingestion."

            // Existing FASTQ files
            initial_fastq_files = channel.fromPath(read_pattern)
                .filter { f -> !(f.parent.simpleName in exclude_list) }
                .map { f -> tuple(f.parent.simpleName, f.simpleName, f) }

            // Real-time watcher on the entire input_dir
            // .until fires when the sequencing summary is created
            def fastq_extensions = ~/.*\.(fq|fastq|fq\.gz|fastq\.gz)$/

            rt_fastq_files = channel.watchPath("${input_dir}/**", 'create,modify')
                .until { f -> f.name ==~ stop_name_pattern }
                .filter { f -> f.name ==~ fastq_extensions }
                .filter { f -> !(f.parent.simpleName in exclude_list) }
                .map { f -> tuple(f.parent.simpleName, f.simpleName, f) }

            read_fastq_raw = initial_fastq_files.concat(rt_fastq_files)
        }

        // Tag samples
        read_fastq = read_fastq_raw
            .map { _parent_name, file_name, f ->
                def (barcode, sample_id) = extractSampleInfo(
                    f.parent, invalid_parents, barcodePattern, runFolderPattern
                )
                sample_id = formatSampleId(sample_id, barcode, RUN_UID)
                tuple(sample_id, file_name, f)
            }

        if (params.include_fastq_fail == false) {
            read_fastq = read_fastq.filter { _parent, _sample, f ->
                !(f.parent.simpleName in exclude_list ||
                  f.parent?.parent?.simpleName in exclude_list)
            }
        }

        if (params.split_fastq_by_size == true) {
            log.info "Splitting FASTQ files into chunks of size: ${params.split_size} bytes"
            ingested_fastq = SplitFastq(read_fastq)
                .flatMap { sample_id, file_id, file_list ->
                    def files = file_list instanceof List ? file_list : [file_list]
                    files.collect { f ->
                        def new_id = f.name.replaceFirst(/\.(fastq|fq)(\.gz)?$/, '')
                        [sample_id, new_id, f]
                    }
                }
        } else {
            ingested_fastq = read_fastq
        }

    emit:
        ingested_fastq
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

process SplitFastq {
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
