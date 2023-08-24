#!/bin/bash

REPO_FOR_REIZEL_LAB=/storage/bfe_reizel/bengst/repo_for_reizel_lab

help() {
  echo Run The WGBS bismark pipeline \(separate dag for each sample\):
  echo USAGE: "$(echo "$0" | awk -F / '{print$NF}')" \{-single-end or -paired-end\} -raw-data-dir \<raw_data_dir\> \
    -genome \<mm10 or hg38\> \[optional\]
  echo
  echo raw_data_dir should contain a dir for each sample containing it\'s fastq files.
  echo -non-directional
  echo Run from the directory you wish the output to be written to.
  echo
  echo products: fastqc report, bismark covaregae file, 100 bp tiles with methylation levels, [bam file containing alignments]
  cat <<EOF

A note about methylation bias correction: I recommend running the pipeline once without additional options, you could
then view the m-bias plots in the MultiQC report. The expected unbiased result is a uniform distribution of the
average methylation levels across read positions. If the results are biased, fix this by either running the methylation
calling jobs again ignoring the biased bases, or running the pipeline again with trimmed reads. Each of these approaches
has it's advantages and disadvantages. Ignoring aligned bases is faster. Trimming the reads may improve alignment if
done correctly, consider trimming R1 and R2 symmetrically and/or using the "--dovetail" bismark option for the bowtie2
aligner.

optional:
-non-directional
  Use for non directional libraries. Instructs Bismark to align to OT, CTOT, OB, CTOB.

-keep-bam
  Don't delete the deduplicated bam files. Useful for running methylation calling jobs again to fix m-bias without
  trimming and rerunning the pipeline, and possibly other downstream analysis.

-ignore_r2 <int>
  From Bismark User Guide:
  ignore the first <int> bp from the 5' end of Read 2 of paired-end sequencing results only.
  Since the first couple of bases in Read 2 of BS-Seq experiments show a severe bias towards non-methylation
  as a result of end-repairing sonicated fragments with unmethylated cytosines (see M-bias plot),
  it is recommended that the first couple of bp of Read 2 are removed before starting downstream analysis.
  Please see the section on M-bias plots in the Bismark User Guide for more details.


-extra-meth_extract-options "multiple quoted options"
handy options (from Bismark manual):
=====================================

Ignore bases in aligned reads.
------------------------------------------------------------------------------------------------------------------
--ignore <int>
    Ignore the first <int> bp from the 5' end of Read 1 (or single-end alignment files) when processing
    the methylation call string. This can remove e.g. a restriction enzyme site at the start of each read or any other
    source of bias (such as PBAT-Seq data).

--ignore_r2 <int>
    Ignore the first <int> bp from the 5' end of Read 2 of paired-end sequencing results only. Since the first couple of
    bases in Read 2 of BS-Seq experiments show a severe bias towards non-methylation as a result of end-repairing
    sonicated fragments with unmethylated cytosines (see M-bias plot), it is recommended that the first couple of
    bp of Read 2 are removed before starting downstream analysis. Please see the section on M-bias plots in the Bismark
    User Guide for more details.

--ignore_3prime <int>
    Ignore the last <int> bp from the 3' end of Read 1 (or single-end alignment files) when processing the methylation
    call string. This can remove unwanted biases from the end of reads.

--ignore_3prime_r2 <int>
    Ignore the last <int> bp from the 3' end of Read 2 of paired-end sequencing results only. This can remove unwanted
    biases from the end of reads.

Other
------------------------------------------------------------------------------------------------------------------------
--no_overlap
    For paired-end reads it is theoretically possible that Read 1 and Read 2 overlap. This option avoids scoring
    overlapping methylation calls twice (only methylation calls of read 1 are used for in the process since read 1 has
    historically higher quality basecalls than read 2). Whilst this option removes a bias towards more methylation calls
    in the center of sequenced fragments it may de facto remove a sizeable proportion of the data. This option is on by
    default for paired-end data but can be disabled using --include_overlap. Default: ON.

--include_overlap
    For paired-end data all methylation calls will be extracted irrespective of whether they overlap or not.
    Default: OFF.

--zero_based
    Write out an additional coverage file (ending in .zero.cov) that uses 0-based genomic start and 1-based genomic end
    coordinates (zero-based, half-open), like used in the bedGraph file, instead of using 1-based coordinates
    throughout. Default: OFF.


-extra-trim-galore-options "multiple quoted options"
handy options (from trim_galore manual):
=====================================

Remove bases from reads before alignment.
------------------------------------------------------------------------------------------------------------------
--clip_R1 <int>         Instructs Trim Galore to remove <int> bp from the 5' end of read 1 (or single-end
                      reads). This may be useful if the qualities were very poor, or if there is some
                      sort of unwanted bias at the 5' end. Default: OFF.

--clip_R2 <int>         Instructs Trim Galore to remove <int> bp from the 5' end of read 2 (paired-end reads
                        only). This may be useful if the qualities were very poor, or if there is some sort
                        of unwanted bias at the 5' end. For paired-end BS-Seq, it is recommended to remove
                        the first few bp because the end-repair reaction may introduce a bias towards low
                        methylation. Please refer to the M-bias plot section in the Bismark User Guide for
                        some examples. Default: OFF.

--three_prime_clip_R1 <int>     Instructs Trim Galore to remove <int> bp from the 3' end of read 1 (or single-end
                        reads) AFTER adapter/quality trimming has been performed. This may remove some unwanted
                        bias from the 3' end that is not directly related to adapter sequence or basecall quality.
                        Default: OFF.

--three_prime_clip_R2 <int>     Instructs Trim Galore to remove <int> bp from the 3' end of read 2 AFTER
                        adapter/quality trimming has been performed. This may remove some unwanted bias from
                        the 3' end that is not directly related to adapter sequence or basecall quality.
                        Default: OFF.

EOF

}

main() {
  if [[ $# -gt 2 ]]; then #don't (re)write cmd.txt if no args
    echo \# the command used to prepare the jobs. Note that parentheses are lost >cmd.txt
    echo \# and need to be added to rerun: -extra-trim-galore-options \"multiple quoted options\" >>cmd.txt
    echo "$0" "$@" >>cmd.txt #TODO: preserve quotes that may be in args
  fi

  n_reads_per_chunk=100000000 #default value (may be overwritten by arg_parse)
  arg_parse "$@"
  mkdir -p logs
  main_write_condor_submission_files $raw_data_dir

  echo Submit the jobs by running: condor_submit_dag ./condor_submission_files/submit_all_bismark_wgbs.dag
  echo Good Luck!
}

write_split_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/split_fastq_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/split_fastq.sh
Arguments = \$(args)
request_cpus = 3
RequestMemory = 250MB
universe = vanilla
log = $(pwd)/logs/$sample_name/${sample_name}_split_fastq.log
output = $(pwd)/logs/$sample_name/${sample_name}_split_fastq.out
error = $(pwd)/logs/$sample_name/${sample_name}_split_fastq.out
queue args from (
  $(
    if [[ $single_end -eq 1 ]]; then
      echo -output-dir $(pwd)/$sample_name/$split/$chunk -chunks $n_chunks -reads-per-chunk $n_reads_per_chunk -input-fastq-file $(realpath $raw_dir/$sample_name/*.fastq.gz)
    else
      echo -output-dir $(pwd)/$sample_name/$split/$chunk -chunks $n_chunks -reads-per-chunk $n_reads_per_chunk -paired-input-fastq-files $(realpath $raw_dir/$sample_name/*.fastq.gz)
    fi
  )
)
#NOTE: may want to gzip fq files after splitting to save disk space (at the cost of more cpu time)
EOF
}

write_trim_jobs_submission_file() {
  chunk=$1
  if [[ $chunk ]]; then
    filename=condor_submission_files/${sample_name}/trim_job_${sample_name}.sub_${chunk}.sub
  else
    filename=condor_submission_files/${sample_name}/trim_job_${sample_name}.sub
  fi
  cat <<EOF >$filename
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/trim_illumina_adaptors.sh
Arguments = \$(args)
request_cpus = 8
RequestMemory = 500MB
universe = vanilla
log = $(pwd)/logs/$sample_name/\$(name)_trim.log
output = $(pwd)/logs/$sample_name/\$(name)_trim.out
error = $(pwd)/logs/$sample_name/\$(name)_trim.out
queue name, args from (
$(
    if [[ $single_end -eq 1 ]]; then
      echo $sample_name$sep$chunk, \" -output-dir $(pwd)/$sample_name/$split/$chunk -input-fastq-file $(pwd)/$sample_name/$split/$chunk/\*.fq $extra_trim_opts\"
    else
      echo $sample_name$sep$chunk, \" -output-dir $(pwd)/$sample_name/$split/$chunk -paired-input-fastq-files $(pwd)/$sample_name/$split/$chunk/\*.fq $extra_trim_opts\"
    fi
  )
)
#NOTE: If storage turns out to be a bottle neck, may want to gzip fq files after trimming (and / or after splitting)
#      to save disk space (at the cost of more cpu time).

EOF
}

write_align_sub_file() {
  chunk=$1
  if [[ $chunk ]]; then
    filename=condor_submission_files/${sample_name}/bismark_align_job_${sample_name}_${chunk}.sub
  else
    filename=condor_submission_files/${sample_name}/bismark_align_job_${sample_name}.sub
  fi
  cat <<EOF >$filename
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/bismark_align.sh
Arguments = \$(args)
request_cpus = 4
RequestMemory = 40GB
universe = vanilla
log = $(pwd)/logs/$samp/\$(name)_bismark_align.log
output = $(pwd)/logs/$samp/\$(name)_bismark_align.out
error = $(pwd)/logs/$samp/\$(name)_bismark_align.out
queue name, args from (
$(

    if [[ $single_end -eq 1 ]]; then
      echo $sample_name$sep$chunk, -output-dir $(pwd)/$sample_name/$split/$chunk -single-end $non_directional -genome $genome $dovetail
    else
      echo $sample_name$sep$chunk, -output-dir $(pwd)/$sample_name/$split/$chunk -paired-end $non_directional -genome $genome $dovetail
    fi
  )
)
EOF
}

write_unite_and_sort_bam_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/unite_and_sort_bam_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/unite_and_sort_bam.sh
Arguments = $(pwd)/$sample_name
request_cpus = 1
RequestMemory = 250MB
universe = vanilla
log = $(pwd)/logs/$sample_name/${sample_name}_unite_and_sort_bam.log
output = $(pwd)/logs/$sample_name/${sample_name}_unite_and_sort_bam.out
error = $(pwd)/logs/$sample_name/${sample_name}_unite_and_sort_bam.out
queue
EOF
}

write_deduplicate_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/deduplicate_job_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/deduplicate.sh
Arguments = \$(args)
request_cpus = 2
RequestMemory = 25GB
universe = vanilla
log = $(pwd)/logs/$sample_name/\$(name)_deduplicate.log
output = $(pwd)/logs/$sample_name/\$(name)_deduplicate.out
error = $(pwd)/logs/$sample_name/\$(name)_deduplicate.out
queue name, args from (
 $sample_name, $(pwd)/$sample_name $split
)
EOF
}

write_methylation_calling_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/methylation_calling_job_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/methylation_calling.sh
Arguments = \$(args)
request_cpus = 10
RequestMemory = 4GB
universe = vanilla
log = $(pwd)/logs/$sample_name/\$(name)_methylation_calling.log
output = $(pwd)/logs/$sample_name/\$(name)_methylation_calling.out
error = $(pwd)/logs/$sample_name/\$(name)_methylation_calling.out
queue name, args from (
  $sample_name, -output-dir $(pwd)/$sample_name $ignore_r2 $keep_trimmed_fq $extra_meth_opts
)
EOF
}

write_bam2nuc_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/bam2nuc_job_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/nucleotide_coverage_report.sh
Arguments = \$(args)
request_cpus = 2
RequestMemory = 10GB
universe = vanilla
log = $(pwd)/logs/sample_name/\$(name)_bam2nuc.log
output = $(pwd)/logs/sample_name/\$(name)_bam2nuc.out
error = $(pwd)/logs/sample_name/\$(name)_bam2nuc.out
queue name, args from (
  $sample_name, -output-dir $(pwd)/$sample_name -genome $genome
)
EOF
}

write_make_tiles_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/make_tiles_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/make_tiles.sh
Arguments = \$(args)
request_cpus = 1
RequestMemory = 30GB
universe = vanilla
log = $(pwd)/logs/$sample_name/(name)_make_tiles.log
output = $(pwd)/logs/$sample_name/(name)_make_tiles.out
error = $(pwd)/logs/$sample_name/(name)_make_tiles.out
queue name, args from (
  $sample_name, -output-dir $(pwd)/$sample_name -genome $genome
)
EOF
}

write_bismark2report_job_submission_file() {
  cat <<EOF >condor_submission_files/${sample_name}/bismark2report_job_${sample_name}.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/bismark2report.sh
Arguments = \$(args)
request_cpus = 1
RequestMemory = 30GB
universe = vanilla
log = $(pwd)/logs/$sample_name/\$(name)_bismark2report.log
output = $(pwd)/logs/$sample_name/\$(name)_bismark2report.out
error = $(pwd)/logs/$sample_name/\$(name)_bismark2report.out
queue name, args from (
  $sample_name, -output-dir $(pwd)/$sample_name
)
EOF
}

write_multiqc_job_submission_file() {
  cat <<EOF >condor_submission_files/multiqc_job.sub
Initialdir = $(pwd)
executable = $REPO_FOR_REIZEL_LAB/run_on_atlas/bismark_wgbs/run_multiqc.sh
Arguments = \$(args)
request_cpus = 1
RequestMemory = 500MB
universe = vanilla
log = $(pwd)/logs/multiqc_job.log
output = $(pwd)/logs/multiqc_job.out
error = $(pwd)/logs/multiqc_job.out
queue args from (
  "$keep_bam -multiqc-args '$(pwd) --outdir multiqc'"
)
EOF
}

write_sample_dag_file() {
  cat <<EOF >condor_submission_files/${sample_name}/bismark_wgbs_${sample_name}.dag
JOB trim_and_qc $(realpath ./condor_submission_files/$sample_name/trim_job_${sample_name}.sub)
JOB bismark_align $(realpath ./condor_submission_files/$sample_name/bismark_align_job_${sample_name}.sub)
JOB deduplicate $(realpath ./condor_submission_files/$sample_name/deduplicate_job_${sample_name}.sub)
JOB meth_call $(realpath ./condor_submission_files/$sample_name/methylation_calling_job_${sample_name}.sub)
JOB make_tiles $(realpath ./condor_submission_files/$sample_name/make_tiles_${sample_name}.sub)
JOB bam2nuc $(realpath ./condor_submission_files/$sample_name/bam2nuc_job_${sample_name}.sub)
JOB bismark2report $(realpath ./condor_submission_files/$sample_name/bismark2report_job_${sample_name}.sub)

PARENT trim_and_qc  CHILD bismark_align
PARENT bismark_align  CHILD deduplicate
PARENT deduplicate  CHILD meth_call bam2nuc
PARENT meth_call  CHILD make_tiles
PARENT meth_call bam2nuc  CHILD bismark2report
EOF
}

main_write_condor_submission_files() { # <raw_dir>
  raw_dir=$1
  sample_names=()
  for sample_name in $(find -L $raw_dir -type d | awk -F / 'NR>1{print $NF}' | sort); do
    #TODO: try to replace this loop with xargs
    #  find -L $raw_dir -type d | awk -F / 'NR>1{print $NF}' | sort | xargs -n1 -P4 sh -c "
    {
      split=
      sep=
      remainder_msg=
      sample_names+=($sample_name)
      mkdir -p condor_submission_files/$sample_name
      mkdir -p logs/$sample_name

      # if fastq file longer than n_reads_per_chunk reads, split it into n_reads_per_chunk read chunks
      echo "Counting reads in $sample_name to see if the fastq file(s) should be split into chunks"
      #  n_reads=$(( $(zcat $(find $raw_dir/$sample_name/ -name "*.fastq.gz" | head -1) | wc -l) / 4 ))
      n_reads=$(($(pigz -cd $(find $raw_dir/$sample_name/ -name "*.fastq.gz" | head -1) | wc -l) / 4))
      n_chunks=$((n_reads / n_reads_per_chunk))

      if [[ $((n_reads % n_reads_per_chunk)) -gt 0 ]]; then
        ((n_chunks++)) # add one more chunk for the remainder reads
        remainder_msg=" + 1 chunk of $((n_reads % n_reads_per_chunk)) reads"
      fi
      echo "n_reads: $n_reads, n_reads_per_chunk: $n_reads_per_chunk"

      if [[ $n_reads -gt $n_reads_per_chunk ]]; then
        echo "fastq files will be split into $((n_chunks - 1)) chunks of $n_reads_per_chunk reads each" "$remainder_msg"
        write_split_job_submission_file
        split="split"
        sep="_"
        #write condor sub files for jobs to align each chunk
        for chunk in $(seq -w 00 $((n_chunks - 1))); do
          write_trim_jobs_submission_file $chunk
          write_align_sub_file $chunk
        done
      else # no splitting of fastq files
        write_trim_jobs_submission_file
        write_align_sub_file
      fi

      #TODO : write_unite_and_sort_bam_job_submission_file?
      #TODO: or use deduplicate job to use the split files with one merged deduplicated output
      write_deduplicate_job_submission_file
      write_methylation_calling_job_submission_file
      write_bam2nuc_job_submission_file
      write_make_tiles_job_submission_file
      write_bismark2report_job_submission_file
      write_sample_dag_file
    }
  done

  write_multiqc_job_submission_file

  #Write the top level submission file to submit all dags
  rm -f ./condor_submission_files/submit_all_bismark_wgbs.dag #incase rerunning the script without delete
  sample_dags=$(realpath condor_submission_files/*.dag)
  touch ./condor_submission_files/submit_all_bismark_wgbs.dag
  fileout=condor_submission_files/submit_all_bismark_wgbs.dag

  i=0
  for dag in $sample_dags; do
    echo SUBDAG EXTERNAL ${sample_names[$i]} $dag >>$fileout
    echo PRIORITY ${sample_names[$i]} $i >>$fileout
    echo >>$fileout
    ((i++))
  done
  echo JOB multiqc $(realpath ./condor_submission_files/multiqc_job.sub) >>$fileout
  echo >>$fileout
  # Old version - all samples submitted at once
  echo PARENT $(for ((k = 0; k <= $i; k++)); do printf "%s " ${sample_names[$k]}; done) CHILD multiqc >>$fileout

  # Another version - Because Atlas' policy of holding jobs that have been submitted more than 3 days ago, break up samples
  # into groups of NUM_PARALLEL_SAMP and have them as parent and child s.t. the next 3 are submitted only after the
  # previous 3 have completed.
  #  NUM_PARALLEL_SAMP=3 #the number of samples that run in parallel
  #  n_samp=${#sample_names[@]}
  #  j=0
  #  if (($NUM_PARALLEL_SAMP > $n_samp)); then
  #    printf "PARENT "
  #    for ((k = 0; k < n_samp; k++)); do printf "%s " ${sample_names[$k]} >> $fileout; done
  #    echo CHILD multiqc >> $fileout
  #  else
  #    for ((j = 0; j < ($n_samp / NUM_PARALLEL_SAMP); j++)); do
  #      printf "PARENT %s %s %s " $(for ((k = 0; k < NUM_PARALLEL_SAMP; k++)); do echo ${sample_names[$j * 3 + $k]}; done) >> $fileout
  #      if ((j != ($n_samp / NUM_PARALLEL_SAMP) - 1)); then
  #        printf "CHILD %s %s %s\n" $(for ((k = NUM_PARALLEL_SAMP; k < 2 * NUM_PARALLEL_SAMP; k++)); do echo ${sample_names[$j * 3 + $k]}; done) >> $fileout
  #      else
  #        if (($n_samp % $NUM_PARALLEL_SAMP)); then
  #          printf "CHILD " >> $fileout
  #          for ((k = NUM_PARALLEL_SAMP; k < NUM_PARALLEL_SAMP + ($n_samp % $NUM_PARALLEL_SAMP); k++)); do
  #            printf "%s " ${sample_names[$k]} >> $fileout
  #          done
  #          printf "\nPARENT " >> $fileout
  #          for ((k = NUM_PARALLEL_SAMP; k < NUM_PARALLEL_SAMP + ($n_samp % $NUM_PARALLEL_SAMP); k++)); do
  #            printf "%s " ${sample_names[$k]} >> $fileout
  #          done
  #        fi
  #        echo CHILD multiqc >> $fileout
  #      fi
  #    done
  #  fi
}

arg_parse() {
  if [[ $# -eq 0 ]]; then
    help
    exit 1
  fi
  while [[ $# -gt 0 ]]; do
    case $1 in
    -h | --help)
      help
      exit 1
      ;;
    -single-end)
      single_end=1
      shift
      ;;
    -paired-end)
      single_end=0
      shift
      ;;
    -non-directional)
      non_directional="--non_directional"
      shift
      ;;
    -raw-data-dir)
      raw_data_dir=$2
      shift
      shift
      ;;
    -keep-bam)
      keep_bam="-keep-bam"
      shift
      ;;
    -keep-trimmed-fq)
      keep_trimmed_fq="-keep-trimmed-fq"
      shift
      ;;
    -dovetail) #seems this is on by default.
      dovetail="-dovetail"
      shift
      ;;
    -genome)
      genome=$2
      shift
      shift
      ;;
    -n-reads-per-chunk) #for splitting fastq files, default is 100M
      n_reads_per_chunk=$2
      shift
      shift
      ;;
    -extra-trim-galore-options)
      extra_trim_opts=$(echo -extra-trim-galore-options \'"$2"\')
      shift
      shift
      ;;
    -extra-meth_extract-options)
      extra_meth_opts=$(echo -extra-options \'"$2"\')
      shift
      shift
      ;;
    -ignore_r2)
      ignore_r2=$(echo -ignore_r2 "$2")
      shift
      shift
      ;;
    *)
      help
      exit 1
      ;;
    esac
  done
}

main "$@"
