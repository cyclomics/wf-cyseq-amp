### 1. Context Viewpoint

The purpose of <ins>wf-cyclomicsseq-amp</ins> is to:

- Analyse CyclomicsSeq amplicon sequencing data to generate consensus reads and call variants in known amplicon loci. Amplicon inserts should no smaller than 50 bp.

    It is assumed that a high-quality polymerase, like phi29, is used for PCR amplification, and that library prep is high-quality and high-complexity. The input sample for PCR should contain at least 5 ng of cfDNA.

This workflow takes as input:
1. A folder containing FASTQ files, or optionally a folder containing several folders for different barcodes each containing a subfolder with FASTQ files. FASTQ files can optionally be gzipped.
2. The human reference genome, version GRCh38.p14.
3. A BED file with the loci for the amplicon inserts amplified during PCR (excluding primers).

What <ins>wf-cyclomicsseq-amp</ins> **is not** meant to do:

- Analyse experiments with amplicon insert sizes smaller than 50 bp.
- Process other technologies' amplicon sequencing data.
- Analyse CyclomicsSeq genome-wide sequencing data, for which there was no PCR amplification of known loci.
- Analyse variants using other reference genomes, or experiments on other species. While this is technically possible, variants will not be annotated.

This workflow is intended to be used either by bioinformaticians through the CLI, or by technicians and researchers through the [EPI2ME](https://epi2me.nanoporetech.com/) GUI.

### 2. Composition and Structure Viewpoint

This is a relatively linear workflow, composed of the following parts, each a different module:

1. Input processing

    Generate unique run IDs, process input folders to ingest FASTQ files (per barcode, if provided), and index reference genome. 

2. Consensus read generation

    Align FASTQ reads to reference genome into BAM files, filter read BAM alignments, and generate consensus FASTQ reads.

3. Consensus read alignment

    Align consensus FASTQ reads to reference genome into BAM files.

4. Variant calling

    Call variants from consensus read BAM alignments within the amplicon loci specified in the provided BED file, and filter and annotate variants using the Ensembl-VEP REST API.

5. Reporting

    Calculate run metrics and generate metric plots, generate variant table, and create a full HTML report.

### 3. Logical Viewpoint

This is a real-time workflow. It handles a stream of FASTQ files inside an input folder. It checks for new FASTQ files until a sequencing summary or DONE file is available.

This datastream allows for data to be processed up to and including consensus read alignment, after which the stream should close (with the presence of a sequencing summary or DONE file) and proceed to variant calling.

The final outputs are:
- A report HTML file
- Consensus read alignment BAM files
- Filtered and annotated variants in a VCF file
- Nextflow execution HTML reports

Results are completely deterministic.

### 4. Dependency Viewpoint

Dependencies shall be managed with Docker containers, which shall be compatible with Singularity/Apptainer. This assumes the user and host OS must be able to run Docker or Singularity/Apptainer images. Conda is not supported. 

Each process should declare a container including the minimal software required for its execution. If two processes require the same minimal software, they may share the same container. Containers should be explicitly versioned in `nextflow.config`. If container versions need to be updated, then their version update should be part of a new release of the entire workflow.

### 5. Information Viewpoint

Inputs:
1. A folder containing FASTQ files, or optionally a folder containing several folders for different barcodes each containing a subfolder with FASTQ files. FASTQ files can optionally be gzipped. Barcode names must follow the pattern `barcode[0-9][0-9]`, and FASTQ folder names must follow the pattern `{fastq_pass,pass}`. FASTQ files must use the extension/suffixes in pattern `{.fastq,.fq,.fastq.gz,.fq.gz}`. 
2. The human reference genome FASTA file, version GRCh38.p14. This file must use an extension/suffix in pattern `{.fa,.fna,.fasta}`
3. A BED file with the loci for the amplicon inserts amplified during PCR (excluding primers). This file must use an extension/suffix in pattern `.bed`.

- If FASTQ files are larger than a user-adjustable maximum number of reads, they shall be split into smaller FASTQ files whose size is the same as the user-adjustable setting.

Outputs:
1. A report HTML file
2. Consensus read alignment BAM files
3. Filtered and annotated variants in a VCF file
4. Nextflow execution HTML reports

If the input folder contained barcode subfolders, than the output shall contain subfolders for each input barcode, each containing the outputs listed above.

TODO:
- How much parallelization is done in the workflow vs within the tool? How should we configure the tools in that regard? How should we choose the tools in that regard?
  - one processes a single file in a single core into a single output file
  - one processes a set of files in a single core into a dir with multiple files
  - one processes a single file with multiple cores into a single output file
  - one processes a set of files with multiple cores into a dir with multiple files

### 6. Patterns Use Viewpoint

The workflow shall prioritize using the least amount of branching possible. A skip pattern is allowed for optional steps (for example, to filter variants). A strategy pattern is allowed for alternative steps (for example, for an alternative variant caller).

Processes involved in the flow of input FASTQ files must use a standard input and output channel structure, consisting of a tuple of at least three elements:

```
tuple val(sample_id), val(file_id), path(file)
```

Rationale:

  - val(sample_id) enables grouping and merging.
  - (file_id) distinguishes the file basename from the actual file, for easy iterations on file processing.
  - path(file) tracks the physical file.

Process inputs and outputs may use channels with more elements or extra channels, as needed, as long as the first channel includes these three elements in this order.

### 7. Interface and Interaction Viewpoint

This workflow has a standard Nextflow CLI, as well as a GUI through [EPI2ME](https://epi2me.nanoporetech.com/).

All configuration is done in `nextflow.config`, including user arguments and user-adjustable parameters.

Error processing:
- If one of the input FASTQ files fails validation during ingestion, then an appropriate error message shall be logged, and the workflow shall proceed with valid files only. If all input FASTQ files fail validation, then the final workflow output shall reflect this lack of data.
- If the reference FASTA and BED files fail validation during ingestion, then the workflow must stop with an appropriate error message..
- If a process fails due to resource errors, then the process may be retried with more allocated resources, if available. If the process fails again, then the workflow must exit with an appropriate error message.
- If a process fails due to any other error, then the workflow must exit with an appropriate error message.
- All workflow errors must be provided in STDOUT and in the final report HTML.

TODO:
- How are Error and exit code semantics organized?
- Are there any file naming conventions?
- What is printed to stdout?
- How is logging performed? What are the different levels of logging? What should go into info, warning, debug?
- What type of configuration parameters do we expect? 
  - What is the expected experience of the user in choosing the right settings?
  - How will user settings be differentiated from developer settings? For example, --input-path is a user setting, while --max-window-size is probably something more internal. 

### 8. State Dynamics Viewpoint

Input data is validated at the start of the workflow by the ingestion module.

Error processing:
- If one of the input FASTQ files fails validation during ingestion, then an appropriate error message shall be logged, and the workflow shall proceed with valid files only. If all input FASTQ files fail validation, then the final workflow output shall reflect this lack of data.
- If the reference FASTA and BED files fail validation during ingestion, then the workflow must stop with an appropriate error message..
- If a process fails due to resource errors, then the process may be retried with more allocated resources, if available. If the process fails again, then the workflow must exit with an appropriate error message.
- If a process fails due to any other error, then the workflow must exit with an appropriate error message.
- All workflow errors must be provided in STDOUT and in the final report HTML.

TODO:
- How can you know that an output file is complete?

### 9. Algorithm Viewpoint

Not applicable.

### 10. Resource Viewpoint

TODO:
- What is the expected max memory usage?
- How does memory scale with additional cores?
- How does runtime scale with additional cores?
- Are there steps where there are memory peaks?
- What is the expected run time given a certain amount of input?
- What is the output file size expected given a certain amount of input?