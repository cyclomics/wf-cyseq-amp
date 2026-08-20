/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    WORKFLOWS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
workflow common_workflow {
    channel.of(params).dump(tag: 'params')

    def reference_path = params.reference_genome ?: 'data/tiny_ref.fasta'
    def reads_glob = params.input_dir ? "${params.input_dir}/${params.read_pattern}" : 'data/dummy.fastq'

    reference_ch = channel.fromPath(reference_path, checkIfExists: true)
    reads_ch = channel.fromPath(reads_glob, checkIfExists: true)

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
process PrepareGenome {
    storeDir "${workDir}/cache/genome/${params.reference}"
    // storeDir "${params.genome_cache_dir}/${params.reference}"
    container params.containers.alnutils
    cpus 1
    memory 1.GB

    input:
    val genome

    output:
    tuple path("genome.fa"), path("genome.fa.fai")

    script:
    def genome_url = genome.fasta
    """
    wget -c -O genome.fa.gz '${genome_url}'
    gunzip genome.fa.gz
    samtools faidx genome.fa
    """
}

process SubsetGenome {
    publishDir { "${params.output_dir}/genome_subset" }, mode: 'copy'
    storeDir "${workDir}/cache/genome/${params.reference}_${bed.baseName}"
    container params.containers.alnutils
    cpus 1
    memory 1.GB

    input:
    tuple path(fasta), path(fai)
    path bed

    output:
    tuple path("genome.subset.fa"), path("genome.subset.fa.fai")

    script:
    """
    awk 'NR > 1' $bed | cut -f1 | sort -u > chromosomes.txt
    
    samtools faidx ${fasta} \\
        \$(cat chromosomes.txt) \\
        > genome.subset.fa

    samtools faidx genome.subset.fa
    """
}

process IndexReference {
    container params.containers.samtools
    cpus 1
    memory 100.MB
    
    input:
        path(reference)
    
    output:
        tuple path(reference), path("${reference}.fai")

    script:
        """
        samtools faidx $reference
        """
}

process PosSortIndexAlignments {
    container params.containers.samtools
    cpus 1
    memory 100.MB

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

process NameSortAlignments {
    publishDir { "${params.output_dir}/${sample_id}/concatemer_alignments" }, mode: 'copy'
    container params.containers.samtools
    cpus 1
    memory 1.GB

    input:
        tuple val(sample_id), val(file_id), path(sam)

    output:
        tuple val(sample_id), val(file_id), path("${file_id}.bam")

    script:
        """
        samtools sort -n -o ${file_id}.bam $sam
        """
}


process GetAmpliconDepth {
    container params.containers.alnutils
    cpus 1
    memory 100.MB
    
    input:
        tuple val(sample_id), val(file_id), path(bam), path(bai)
        path(bed)

    output:
        tuple val(sample_id), val(file_id), path("${sample_id}_amplicon_depth.yml")

    script:
        """
        awk 'NR > 1' $bed > bed_no_header.bed

        samtools depth -a -J -b bed_no_header.bed $bam > ${sample_id}_depth.tsv
        get_amplicon_depth.py ${sample_id}_depth.tsv bed_no_header.bed ${sample_id}_amplicon_depth.yml
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