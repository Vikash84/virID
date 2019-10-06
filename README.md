# virID
Viral Identification and Discovery - A viral characterization pipeline built in [Nextflow](https://www.nextflow.io/).

![Pipeline schematic](/resources/images/2019_10_06_virID_workflow.jpg)

Quickstart
----
The only software requirements for running this pipeline is the [Conda](https://docs.conda.io/en/latest/miniconda.html) package manager and [Nextflow](https://www.nextflow.io/) version 19.07.0. When the pipeline is first initiated, Nextflow will create a conda virtual environment containing all required additional software, and all processess will run in this in virtual environment. The only other things you need to take care of are making the DIAMOND and megablast databases, as well as making any changes to the executor depending on the cluster infrastructure you plan to run this pipeline on. There are more detailed descriptions of these steps below.

1. Download Nextflow version 19.07.0  
`conda install nextflow=19.07.0`  

2. Prepare DIAMOND and megablast databases. 

3. Configure input parameters in `nextflow.config`.  

4. Change executor in `nextflow.config` if not using a SLURM cluster.

4. `nextflow run jnoms/virID --reads "path/to/reads/*fastq" --out_dir "path/to/output/dir"`


## Description
The purpose of virID is to assemble and classify microorganisms present in next-generation sequencing data. The steps of this pipeline are as follows:
1) Input fastqs are split into a paired file containing interleaved paired reads, and an unpaired file containing unpaired reads. Thus, each sample should be added to this pipeline as a single fastq containing both paired and unpaired reads.
2) Reads are assembled with the SPAdes assembler - SPAdes, metaSPAdes, or rnaSPAdes can be specified.
3) bwa mem is used to map reads back to contigs.
4) The DIAMOND and megablast aligners are used for taxonomic assignment of assembled contigs.
5) DIAMOND and megablast output files are translated to a taxonomic output following last-common-ancestor (LCA) calculation for each query contig.
6) (virID v2.0+) Contigs are queried with megablast against a nonredundant database of common cloning vectors. Contigs that are assigned to these sequences are flagged.
6) DIAMOND and megablast taxonomic outputs and contig count information are merged to a comprehensive taxonomic output, and unassigned contigs are flagged. Counts outputs, one for each DIAMOND and megablast, are generated which display the counts at every taxonomic level. There is a section below that describes the output files in more detail.

While this pipeline is organized in Nextflow, every process is capabale of being used and tested independently of Nextflow as a bash or python script. Execute any python script (with -h) or bash script (without arguments) for detailed instructions on how to run them.

## Prepare databases
This workflow requires three databases: 1) A DIAMOND database for search, 2) A nucleotide blast database for search, and 3) a contaminant nucleotide blast database (virID v2.0+).

A DIAMOND database can be generated by following the DIAMOND [manual](https://github.com/bbuchfink/diamond/raw/master/diamond_manual.pdf). I recommend generating a database using the RefSeq nonredundant protein fastas present at [ftp://ftp.ncbi.nlm.nih.gov/refseq/release/]. When making the DIAMOND database with `diamond makedb` you must use the `--taxonmap` and `--taxonnodes` switches.  
```
diamond makedb \
--in <FASTA> \
-d <path to output database> \
--taxonmap <path to prot.accession2taxid.gz from ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/accession2taxid/prot.accession2taxid.gz> \
--taxonnodes <path to nodes.dmp from ftp://ftp.ncbi.nlm.nih.gov/pub/taxonomy/taxdmp.zip.
```

For blast seach, you must download the blast v5 nucleotide database using the same version of blast+ used in this script and installed via the conda .yml file. There is sometimes a bug where this database will not work - you may have to delete the last line of nt_v5.nal that specifies a volume of the blast database that is not actually present.  
`update_blastdb.pl --blastdb_version 5 nt_v5 --decompress`

A nucleotide contaminant blast database is included with this pipeline. This database was generated from [Univec_ core](https://www.ncbi.nlm.nih.gov/tools/vecscreen/univec/?), which is a nonredundant list of common laboratory cloning vectors. I have also added some additional vectors to this database.

## Configure executor and resources
**Executor:** The Nextflow executor, explained [here](https://www.nextflow.io/docs/latest/executor.html), dictates how Nextflow will run each process. virID is currently set up to use a SLURM cluster, but you can easily change this by altering the executor in `nextflow.config`. Nextflow takes care of all cluster submissions and automatically parallelizes everything. If you are using a different cluster infrastructure, change the "executor" value from 'slurm' to the appropriate infrastructure. In addition, each nextflow module (in `bin/modules/`) contains a `beforeScript` line that dictates code to run prior to running the module. Here, I have added `module load gcc conda2`, which loads the GCC compiler and the conda package manager in my slurm cluster. If this is not relevant to you, remove this code.

**Resources:** I have set up virID with *dynamic resources!* Each process will request a different amount of resources depending on the size of the input files. In addition, upon failure the process will restart with increased resources, and will restart a up to three times (configurable with the `maxRetries` setting in `nextflow.config`).

## Inputs and parameters
In general, all input values and parameters for this script must be entered in the `nextflow.config` file. Most of the parameters are already filled out for you, but you may want to change some of them.  

#### Input and output
**params.out_dir:** Desired output directory.  
**params.reads:** A glob detailing the location of reads to be processed through this pipeline. NOTE, input reads for one sample should be in one fastq. This script will process the fastq into an interleaved (paired) fastq and a separate unpaired fastq. *There should be a single fastq for each input sample.* A value of `"raw_reads/*fastq"` is an appropriate input for this parameter, and will select as input all fastq files in the directory `raw_reads`. Make sure to wrap in quotes!  

#### SPAdes
**params.spades_type:** Options are 'meta', 'rna', and 'regular'. This specifies whether to use metaspades.py, rnaspades.py, or spades.py.  
**params.temp_dir:** This specifies the location of the SPAdes temporary directory.  

#### DIAMOND
**params.diamond_database:** Path to the diamond database. Wrap all paths in quotes!  
**params.diamond_evalue:** The maximum evalue of a match to be reported as an alignment by DIAMOND. In general I am a fan of setting this at 10, which is quite high. Lower values, such as 0.001, are more stringent and have fewer false positives.  
**params.diamond_outfmt:** This dictates the output format from DIAMOND. This pipeline requires an outfmt of "6 qseqid stitle sseqid staxids evalue bitscore pident length", which is specified in the config file.  

#### BLAST
**params.blast_database:** Path to the blast nt database. Wrap all paths in quotes!  
**params.blast_evalue:** The maximum evalue of a match to be reported as an alignment by blast. In general I am a fan of setting this at 10, which is quite high. Lower values, such as 0.001, are more stringent and have fewer false positives.  
**params.blast_type:** This controls the 'task' switch of blast, and specified whether to run 'megablast', 'dc-megablast', or 'blastn'. I recommend 'megablast', else it will be quite slow.  
**params.blast_outfmt:** This dictates the output format from BLAST. This pipeline requires an outfmt of "6 qseqid stitle sseqid staxid evalue bitscore pident length", which is specified in the config file.  
**params.blast_log_file:** This is a file that will contain log information from the blast bash script.  
**params.blast_max_hsphs:** This is the maximum number of alignments per query-subject pair. Recommend setting at 1.  
**params.blast_max_targets:** This is the maximum number of separate hits that are allowed for each query.  
**params.blast_restrict_to_taxids:** This parameter lets you limited the blast search to a specified taxonID. This causes an extreme speedup, and is helpful for testing this pipeline. Not compatible with params.blast_ignore_taxids.  
**params.blast_ignore_taxids:** This parameter lets you ignore all hits of a particular taxonID.  


#### BLAST/DIAMOND conversion
**params.within_percent_of_top_score:** When finding the LCA of all matches for a given query sequence, this details how close to the maximum bitscore a match must be to be considered in the LCA classification. If this is set at 1, for example, all potential alignments within 1 percent of the highest bitscore for a query sequence will be considered in the LCA classification. **NOTE**: This is limited intrinsically by the DIAMOND -top parameter, which is set at 1. Thus, DIAMOND will only output assignments within 1% of the top bitscore anyway. I will add a switch to change the DIAMOND -top parameter in a future release.  
**params.taxid_blacklist:** Path to a file containing taxonIDs to be blacklisted. I have included a file in this github repository. Assignments containing one of these taxonIDs will be discarded before LCA calculation.  
**params.diamond_readable_colnames:** These are the more-readable column names that will be reported in the output from DIAMOND. If you change the outfmt, change this line accordingly.  
**params.blast_readable_colnames:** These are the more-readable column names that will be reported in the output from BLAST. If you change the outfmt, change this line accordingly.  
**params.taxonomy_column:** This details which of the colnames contains the taxonID.  
**params.score_column:** This details which of the colnames should be used for calculating the top score. I use bitscore, but you could technically set this as pident or length or evalue to sort by one of those parameters instead.  

#### BLAST/DIAMOND conversion
**params.blast_contaminant_database:** Path the the vector contaminant database.  
**params.blast_contaminant_evalue:** Required evalue for assignment. I recommend setting this to be fairly stringent.  
**params.blast_contaminant_outfmt:** Outformat. For ease, I default to the normal blast outfmt.  
**params.blast_contaminant_log_file:** Path to the log file.  
**params.blast_contaminant_type:** The -task blast parameter. I recommend megablast or else it will be way too slow, and unnecessary.  
**params.blast_contaminant_max_hsphs:** This is the maximum number of alignments per query-subject pair. Recommend setting at 1.  
**params.blast_contaminant_max_targets:** This is the maximum number of separate hits that are allowed for each query. Because this is a screen, and we only need to know if a query has at least one assignment in the contaminant database, I recommend setting at 1.  

## Description of output files
1. Each process will copy its outfiles to params.out_dir. You can disable this setting my removing the `publishDir` line from each module file.  
2. The `our_dir/results` dir will contain the main pipeline outputs:

**${sampleID}_merged.tsv:** This is a tab-delimited file containing assignment information for each contig. Each contig takes up two lines, where one line details the BLAST assignment information and one details the DIAMOND assignment information. Columns from `seq_title` to `length` are a comma-delimited list detailing information from all DIAMOND or blast hits that were considered in the LCA calculation. Starting at `LCA_taxonID`, the taxonomic information is that of the LCA of these hits.

Column names include:  
`query_ID:`               Contig name  
`seq_title:`              Title of hits (comma-delimited list)  
`seq_ID:`                 Acession IDs of hits (comma-delimited list)  
`taxonID:`                taxonID of hits (comma-delimited list)  
`evalue:`                 Evalues of hists (comma-delimited list)  
`bitscore:`               Bitscores of hits (comma-delimited list)  
`pident:`                 Percent identity of each hit (comma-delimited list)  
`length:`                 Length of the alignment for each hit (comma-delimited list)  
`LCA_taxonID:`            The taxonID of the LCA of each hit.  
`superkingdom:`           LCA superkingdom  
`kingdom:`                LCA kingdom  
`phylum:`                 LCA phylum  
`class:`                  LCA class  
`order:`                  LCA order  
`family:`                 LCA family  
`genus:`                  LCA genus  
`species:`                LCA species  
`strain:`                 LCA strain  
`read_count:`             Number of input reads that map to the contig.  
`average_fold:`           Average fold coverage of the input reads on the contig.  
`covered_percent:`        Percentage of the contig covered by input reads.  
`potential_contaminant:`  1 if assigned to the contaminant vector database, 0 otherwise. (Column excluded if no contaminants found).  

**${sampleID}_blast_counts.tsv and ${sampleID}_diamond_counts.tsv:** Here, the read_count for each contig is distributed to each taxonomic level of the LCA of that contig. For example, if a contig has an LCA of sk__superkingdom/k__kingdom/f__polyomaviridae and has a read_count of 10, 10 reads are assigned to each f__polyomaviridae, k__kingdom, and sk__superkingdom. These outputs detail the results based on the blast or DIAMOND assignments, respectively. The columns include:  
`taxonID`      The taxonID  
`lineage`      The name of each taxon in the lineage of the taxonID.  
`superkingdom` The superkingdom of the taxonID  
`taxon`        The name of the taxon  
`level`        The level of the taxon (i.e. kingdom, or family, etc)  
`count`        The total number of reads assigned to that taxon.  

## Citation
The paper you should cite when using this program is in progress. For now, please cite this repository.

This pipeline is nothing without the excellent programs virID makes use of. Please cite these programs in addition to virID if you use virID in any publication! I'll list them below, in no particular order:  
SPAdes  
seqtk  
BWA  
Samtools  
bbtools  
Blast+  
DIAMOND  
ETE3  
Anytree
