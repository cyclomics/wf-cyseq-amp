/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow ingressFastqFiles {
    take:
        input_dir
        read_pattern

    main:
        def runUID = generateUid( (('A'..'Z')+('a'..'z')+('0'..'9')).join(), 7 )
        def excludeList = getFastqExcludeList()
        def invalidParents = getInvalidParents()
        def barcodePattern = getMinKnowBarcodeFolderPattern()
        def runFolderPattern = getMinKnowAutoRunFolderPattern()

        if (params.input_dir.endsWith("/")) {
            read_pattern = "${params.input_dir}${params.read_pattern}"
        }
        else {
            read_pattern = "${params.input_dir}/${params.read_pattern}"
        }

        read_fastq = channel.fromPath(read_pattern, checkIfExists: true)
        read_fastq.dump(tag: "read_fastq_all")

        if (params.include_fastq_fail) {
            read_fastq = read_fastq
        }
        else {
            read_fastq = read_fastq.filter { 
                !(it.Parent.SimpleName in excludeList || it.Parent?.Parent.SimpleName in excludeList) 
            }
        }
        read_fastq.dump(tag: "read_fastq_no_fail")

        read_fastq = read_fastq.map { it ->
            def (barcode, sample_ID) = getValidParent(it.Parent, invalidParents, barcodePattern, runFolderPattern)
            
            if (params.sample_id != "") {
                    sample_ID = params.sample_id.toString()
                }
                sample_ID = sample_ID.replaceAll("\\s+", "_")
                sample_ID = sample_ID + "_" + runUID
                if (barcode != "") {
                    sample_ID = sample_ID + "_" + barcode
                }

                tuple(sample_ID, it.simpleName, it)
            }
        
        read_fastq.dump(tag: "read_fastq_sample_tagged")
        read_fastq.dump(tag: "read_fastq")

    emit:
        read_fastq
}


/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
def generateUid(String alphabet, int n) {
    (1..n).collect { alphabet[ new java.util.Random().nextInt( alphabet.length() ) ] }.join()
}

def getFastqExcludeList() {
    ['fastq_fail', 'fail']
}

def getInvalidParents() {
    ['fastq', 'pass', 'fastq_pass', 'fastq_fail', 'fail', 'home']
}

def getMinKnowBarcodeFolderPattern() {
    ~/^barcode\d{2}$|unclassified/
}

def getMinKnowAutoRunFolderPattern() {
    ~/^\d{8}_\d{4}_.+/
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


