<p>
  <img src="assets/logo_named.png" alt="logo" width="200" align="left" />
  <img src="assets/tagline.png" alt="tagline" width="150" align="right" />
</p>

<br>

# CySeq Amplicon

This workflow uses concatemeric CySeq reads as input to generate consensus reads in real-time, which will then be used to call variants over a reference.

> <b>Expected use case:</b> <br>
> This workflow is designed specifically for ONT long-read sequencing reads generated using a CySeq (S or L) protocol in association with a PCR amplification panel. It expects reads to pile up on known genomic loci. The workflow will generate consensus reads in those loci and use the consensus pileups to call variants within the loci.

<details>
  <summary><b>Table of contents</b></summary>

  - [Input requirements](#input-requirements)
  - [System requirements](#system-requirements)
  - [Software requirements](#software-requirements)
  - [General usage](#general-usage)
  - [Troubleshooting](#troubleshooting)

</details>

## Input requirements

The following inputs are mandatory:

| Input | Format | Description |
| ----- | ------ | ----------- |
| Input data folder | Directory | A MinKnow sequencing output folder containing the `fastq_pass` subfolder, which may optionally contain `barcode` subfolders. This provided output folder is the same folder where MinKnow will write the sequencing summary file, which is necessary to flag the end of the real-time file ingestion. |
| Reference genome | FASTA | FASTA human reference genome version GRCh38.p14, [ideally NCBI's major release for alignment pipelines provided here](https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/001/405/GCF_000001405.40_GRCh38.p14/GRCh38_major_release_seqs_for_alignment_pipelines/GCA_000001405.15_GRCh38_no_alt_analysis_set.fna.gz). This file must be unzipped. |
| Genomic loci | BED | BED file with the genomic loci of interest, in relation to the above reference. <mark>TODO: add example</mark> |

## Software requirements

This workflow makes use of Nextflow and Docker to execute and manage all other dependencies.

If you are executing this workflow through [EPI2ME](#https://epi2me.nanoporetech.com/), then both these dependencies should be part of [its installation instructions](https://epi2me.nanoporetech.com/epi2me-docs/installation/). If you need to install them manually, please follow their official documentation:

- [Nextflow](https://docs.seqera.io/nextflow/install) (v25.04 or higher)
- [Docker](https://docs.docker.com/get-started/get-docker/)

## System requirements

The pipeline expects at least 16 threads to be available and 32GB of RAM. We recommend at least 64 GB of RAM to decrease the runtime significantly.

## General usage

<details>
  <summary><b><font size="+1">Through EPI2ME</font></b></summary>

  This pipeline is compatible with the EPI2ME platform by ONT. Please see [ONT's installation guide](https://epi2me.nanoporetech.com/epi2me-docs/quickstart/).

  Installation inside EPI2ME:
  1. Go to workflows by clicking on "installed workflows", or click the workflows icon in the top bar.
  2. click "Import workflow".
  3. Paste "https://github.com/cyclomics/cyclomicsseq" into the text bar and click Import workflow.

  Updating workflow on EPI2ME:

</details>

<details>
  <summary><b><font size="+1">Through command line</font></b></summary>

  <mark>TODO</mark>

  In this section we assume that you have docker and nextflow installed on your system, if so running the pipeline is straightforward. You can run the pipeline directly from the repo.

  ```bash
  nextflow run cyclomics/wf-cycmomicsseq-amp --input_dir tests/informed/fastq_pass/ --reference tests/informed/tp53.fasta --regions <TODO> --output_dir results/ 
  ```
</details>

## Troubleshooting

If you encounter any issues with the workflow where there is unexpected behaviour, then we kindly request that you [submit an issue on the GitHub repository](https://github.com/cyclomics/wf-cyclomicsseq-amp/issues). This helps the development team address your issues quickly.

Alternatively, you can e-mail Cyclomics directly at info@cyclomics.com.
