# wf-cyseq-amp

This workflow uses concatemeric CySeq reads as input to generate consensus reads in real-time, which will then be used to call variants over a reference.

- [Dependencies](#dependencies)
- [Expected use case](#expected-use-case)
- [System requirements](#system-requirements)
- [General usage](#general-usage)
  - [Through EPI2ME](#through-epi2me)
  - [Command line use for Linux](#command-line-use-for-linux)

## Dependencies and requirements

Click for installation instructions:

- [Nextflow](#dependency-installation) (v23.04.2 or higher)
- [Docker](#dependency-installation) or [Apptainer/Singularity](#dependency-installation)


## Expected use case

This workflow is designed specifically for ONT long-read sequencing reads generated using a CySeq (S or L) protocol in association with a PCR amplification panel. It expects reads to pile up on known genomic loci. The workflow will generate consensus reads in those loci and use the consensus pileups to call variants within the loci. As such, the following inputs are necessary:

- A MinKnow sequencing output folder containing the `fastq_pass` subfolder, which may optionally contain `barcode` subfolders. This provided output folder is the same folder where MinKnow will write the sequencing summary file, which is necessary to flag the end of the real-time file ingestion.
- FASTA human reference genome version GRCh38.p14, as provided [here](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz). #TODO: add download instructions
- BED file with the genomic loci of interest, in relation to the above reference. #TODO: add example

The reference genome can be downloaded through the command line thus:
``` bash
wget https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz
gunzip GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz
```

## System requirements

The pipeline expects at least 16 threads to be available and 32GB of RAM. We recommend at least 64 GB of RAM to decrease the runtime significantly.


## General usage

### Through EPI2ME

This pipeline is compatible with the EPI2ME platform by ONT. Please see [ONT's installation guide](https://epi2me.nanoporetech.com/epi2me-docs/quickstart/).

Installation inside EPI2ME:
1. Go to workflows by clicking on "installed workflows", or click the workflows icon in the top bar.
2. click "Import workflow".
3. Paste "https://github.com/cyclomics/cyclomicsseq" into the text bar and click Import workflow.

Updating workflow on EPI2ME:

### Command line use for Linux

In this section we assume that you have docker and nextflow installed on your system, if so running the pipeline is straightforward. You can run the pipeline directly from this repo, or pull it yourself and point nextflow towards it.

```bash
nextflow run cyclomics/cycmomicsseq -profile docker --input_read_dir tests/informed/fastq_pass/ --output_dir results/ --reference tests/informed/tp53.fasta
```

The command above will automatically pull the CyclomicsSeq from GitHub. If you prefer to manually clone the repository before running the pipeline, you can do so with the following command:

```bash
git clone git@github.com:cyclomics/cyclomicsseq.git
cd cyclomicsseq
nextflow run main.nf -profile docker --input_read_dir tests/informed/fastq_pass/ --output_dir results/ --reference tests/informed/tp53.fasta
```

