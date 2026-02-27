/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow common_workflow {
    channel.of(params).dump(tag: 'params')

    def reference_path = params.reference_genome ?: 'data/tiny_ref.fasta'
    def reads_glob = params.input_dir ? "${params.input_dir}/${params.read_pattern}" : 'data/dummy.fastq'

    def reference_ch = channel.fromPath(reference_path, checkIfExists: true)
    def reads_ch = channel.fromPath(reads_glob, checkIfExists: true)

    reference_ch.dump(tag: 'reference_ch')
    reads_ch.dump(tag: 'reads_ch')
    TestProcess(reference_ch)
    GetFirstRead(reads_ch)

    TestProcess.out.view()
    GetFirstRead.out.view()
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    PROCESSES
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
process SplitReadFilesOnNumberOfReads {
    container params.containers.seqkit
    cpus 4

    input:
        tuple val(sample_id), val(file_id), path(fq)

    output:
        tuple val(sample_id), val(file_id), path("split/${file_id}_*.fastq")

    script:
        """
        seqkit split -j ${task.cpus} -e .gz -s $params.max_fastq_size --by-size-prefix ${file_id}_ -O split $fq
        gunzip split/*.gz
        """
}

process FilterShortReads {
    container params.containers.seqkit

    input:
        tuple val(sample_id), val(file_id), path(fq)

    output:
        tuple val(sample_id), val("${file_id}_filtered"), path("${file_id}_filtered.fastq")

    script:
        """
        seqkit seq -m ${params.min_raw_length} $fq > "${fq.simpleName}_filtered.fastq"
        """
}

process IndexReference {
    container params.containers.samtools
    
    input:
        path(reference)
    
    output:
        tuple path(reference), path("${reference}.fai")

    script:
        """
        samtools faidx $reference
        """
}

process SortIndexAlignments {
    container params.containers.samtools

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.bam"), path("${file_id}.bam.bai") 

    script:
        """
        samtools sort -o ${file_id}.bam $sam
        samtools index ${file_id}.bam
        """
}


process TestProcess {
    label 'standard'
    container params.containers.ubuntu

    input:
        path reference_genome

    output:
        stdout

    script:
    // This is a test process to check if the reference genome can be read correctly.
    // Normally you would not check params in a process, but this is just for demonstration purposes.
    // As we also have a test on error handling, we want to make sure that the process fails if the reference genome cannot be read.
        """
        if [[ ! -f $reference_genome ]]; then
            echo "File does not exist: $reference_genome" >&2
            exit 1
        fi
        head -n 1 $reference_genome
        """
}

process GetFirstRead {
    cpus 1
    memory '2 GB'
    container params.containers.ubuntu

    input:
        path read_fastq

    output:
        path("*.fastq")

    script:
        """
        head -n 4 $read_fastq > first_read.fastq
        """

    stub:
        """
        head -n 4 $read_fastq > first_read.fastq
        """
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/