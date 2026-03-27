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
        tuple val(sample_id), val("${file_id}"), path("${file_id}_filtered.fastq")

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


process CountNumberOfReads {
    container params.containers.alnutils
    publishDir { "${params.output_dir}/${sample_id}/report/raw_counts" }, mode: 'copy'
    tag "${sample_id}_${file_id}_${type}"

    input:
        tuple val(sample_id), val(file_id), path(fq)
        val(type)

    output:
        tuple val(sample_id), val(file_id), path("number_of_reads_${type}_${sample_id}_${file_id}.json")

    script:
        """
        set -euo pipefail

        if [[ "${fq}" == *.gz ]]; then
            lines=\$(zcat ${fq} | wc -l)
        else
            lines=\$(wc -l < ${fq})
        fi

        reads=\$((lines / 4))

        cat << EOF > number_of_reads_${type}_${sample_id}_${file_id}.json
{
"sample_id": "${sample_id}",
"file_id": "${file_id}",
"type": "${type}",
"reads": \$reads
}
EOF
        """
}

process UpdateTotalReads {
    container params.containers.alnutils
    maxForks 1
    publishDir "${params.output_dir}/report/counts", mode: 'copy'

    input:
        tuple val(type), val(sample_id), path(json_file)
        path(final_totals_file)

    output:
        path("number_of_reads_running.json")

    script:
        """
        sum_reads.py \
            --sample_id "${sample_id}" \
            --json_file "${json_file}" \
            --published_file "${final_totals_file}"
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