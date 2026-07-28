<p>
  <img src="assets/header.png" alt="header"/>
</p>

# CySeq Amplicon

This workflow uses concatemeric CySeq reads of specific amplicon targets as input to generate consensus reads in real time, which will then be used to call variants within the amplified loci.

> <b>Expected use case:</b> <br>
> This workflow is designed specifically for ONT long-read sequencing reads generated using a CySeq (Short Fragment or Long Fragment) sequencing kit in association with a PCR amplification panel. It expects reads to accumulate on known genomic loci, as high read depth is required for low frequency variant calling. The workflow will generate consensus reads in those loci and use the consensus reads to call variants within the loci.

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
| Sample name | Text | Required for EPI2ME runs only. A descriptive name for your analysis run, relating to the sample being analysed. |
| Input data folder | Directory | A MinKNOW sequencing output folder containing the `fastq_pass` subfolder, which may optionally contain `barcode` subfolders. This provided output folder is the same folder where MinKNOW will write the sequencing summary file, which is necessary to flag the end of the real-time file ingestion. |
| Reference genome | FASTA | The reference genome is used to align consensus reads and identify sequence variants. Currently supported human genomes are ‘GRCh38.p14’ and ‘GRCh37.p13’. The selected genome data will be downloaded automatically Additionally, options ‘Lambda’ and ‘dev’ will download the Escherichia Lambda phage genome reference, and will inactivate variant annotation. |
| Genomic loci | BED | BED file with the genomic loci of interest, in relation to the above reference. |

## Software requirements

This workflow makes use of Nextflow and Docker to execute and manage all other dependencies.

If you are executing this workflow through [EPI2ME](https://epi2me.nanoporetech.com/), then both these dependencies should be part of [its installation instructions](https://epi2me.nanoporetech.com/epi2me-docs/installation/). If you need to install them manually, please follow their official documentation:

- [Nextflow](https://docs.seqera.io/nextflow/install) (v23.04 or higher)
- [Docker](https://docs.docker.com/get-started/get-docker/)

## System requirements

The workflow expects at least 16 CPUs to be available and 32 GB of RAM. Please ensure you have at least 50 GB of disk space available.

We recommend at least 64 CPUs and 160 GB of RAM to decrease the runtime significantly. Primarily increasing the RAM allocation will allow the workflow to run more demanding processes in parallel, decreasing runtime. To further decrease runtime, allow 20 GB extra RAM for every 8 additional CPUs.

## General usage

<details>
  <summary><b><font size="+1">Through EPI2ME</font></b></summary>

  This pipeline is compatible with the EPI2ME platform by ONT. Please see [ONT's installation guide](https://epi2me.nanoporetech.com/epi2me-docs/quickstart/).

  **Installation on EPI2ME:**
  1. Open EPI2ME. Either login or click on the ellipsis ('...') and continue as guest.
  2. Navigate to 'Launch'.
  3. Click 'Import workflow'.
  4. Click 'Import from GitHub'
  3. Paste `https://github.com/cyclomics/wf-cyseq-amp` into the text bar and click 'Import workflow'.

  **Updating workflow on EPI2ME:**
  1. Open EPI2ME. Either login or click on the ellipsis ('...') and continue as guest.
  2. Navigate to ‘Launch’.
  3. Select ‘CySeq Amplicon’.
  4. Click ‘Options’.
  5. Select ‘Check for updates’
  6. EPI2ME will download the latest available workflow release.

</details>

<details>
  <summary><b><font size="+1">Through command line</font></b></summary>

  In this section we assume that you have docker and nextflow installed on your system, if so running the pipeline is straightforward. You can run the pipeline directly from the repo:

  ```bash
  nextflow run cyclomics/wf-cyseq-amp \
    --input_dir /path/to/run_directory \
    --reference /path/to/reference.fasta \
    --regions /path/to/targets.bed \
    --output_dir /path/to/results
  ```
</details>

## Troubleshooting

If you encounter any issues with the workflow where there is unexpected behaviour, then we kindly request that you [submit an issue on the GitHub repository](https://github.com/cyclomics/wf-cyseq-amp/issues). This helps the development team address your issues quickly.

Alternatively, you can e-mail Cyclomics directly at cyseq@cyclomics.com.
