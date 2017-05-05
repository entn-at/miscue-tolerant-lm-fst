#!/bin/bash

# This script creates a decoding graph for all entries in a Kaldi data directory
# text file. Format for each line is:
#   <UTTID> <prompt of many words>
# The graphs are created in subdirectories of the given model directory.
# An .scp file is created in the data directory, which gives for each uttid
# the corresponding graph, in the format:
#   <UTTID> <path-to-HCLG.fst>

set -e -u
set -o pipefail

OOV="<SPOKEN_NOISE>"
while getopts "o:" OPTNAME; do
  case "$OPTNAME" in
    o) OOV="$OPTARG";;
  esac
done
shift $((OPTIND - 1))

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <dictsrcdir> <modeldir> <datadir> <workdir>" >&2 
  exit 1
fi

dictsrcdir="$1"
modeldir="$2"
datadir="$3"
workdir="$4"

textfile="$datadir/text" 
required="$textfile $modeldir/final.mdl $modeldir/tree"
for f in $required; do
  [ ! -f "$f" ] && echo "$0 expected $f to exist" >&2 && exit 1;
done

langdir="$workdir"/lang
localdictsrc="$langdir"/dict
langtmpdir="$langdir"/tmp

mkdir -p "$langtmpdir" "$localdictsrc"
trap "rm -rf $langtmpdir $localdictsrc $langdir" EXIT HUP INT PIPE TERM

[ -f path.sh ] && . ./path.sh

cp -a "$dictsrcdir"/* "$localdictsrc"
rm "$localdictsrc"/lexicon*.txt

kaldi-scripts/make_extended_lexicon.py --oov "$OOV" "$dictsrcdir" "$localdictsrc" "$textfile"
utils/prepare_lang.sh "$localdictsrc" "$OOV" "$langtmpdir" "$langdir"
cp "$localdictsrc"/homophones.txt "$langdir"
rm -rf "$langtmpdir"

scale_opts="--transition-scale=1.0 --self-loop-scale=0.1"

graphsdir="$modeldir/graphs_mtlm_"$(basename "$datadir")
graphsscp="$graphsdir/HCLG.fsts.scp"
#Make sure dir exists but graphsscp does not:
mkdir -p "$graphsdir"
rm -f "$graphsscp"


#The while loop makes a text format G FST 
#for each utterance in $textfile, then and echoes that:
cat "$textfile" | while read promptline; do
  uttid=$(echo "$promptline" | awk '{print $1}' )
  prompt=$(echo "$promptline" | cut -f 2- -d " " )
  #echo "Processing: $uttid"
  promptdir="$workdir/$uttid"
  #graphdir="$graphsdir/TMP_$uttid"
  mkdir -p "$promptdir"
  echo "$uttid" #Header
  echo "$prompt"  | ./make_one_miscue_tolerant_lm.py \
    --homophones "$langdir"/homophones.txt --rubbish-label "$OOV" |\
    utils/eps2disambig.pl |\
    utils/sym2int.pl -f 3-4 "$langdir"/words.txt >&1
  echo #empty line as separator
  #  | utils/eps2disambig.pl |\
  #  fstcompile --isymbols="$langdir"/words.txt --osymbols="$langdir"/words.txt |\
  #  fstarcsort --sort_type=ilabel > "$langdir"/G.fst
  #cp "$langdir"/{G.fst,words.txt} "$promptdir"

  #utils/mkgraph.sh "$langdir" "$modeldir" "$graphdir"
  #
  #pathtograph="$graphdir/HCLG.fst"
  #[ ! -f "$pathtograph" ] && echo "Looks like graph creation for $pathtograph failed" >&2 && exit 1;
  #echo "$uttid $pathtograph" >> "$graphsscp"
  ##rm -rf "$promptdir"
  #rm -rf "$langdir"/G.fst "$langdir"/tmp
done |\
  compile-train-graphs-fsts $scale_opts --read-disambig-syms="$langdir"/phones/disambig.int \
    "$modeldir"/tree $modeldir/final.mdl "$langdir"/L_disambig.fst ark:- \
  ark,scp:"$graphsdir"/HCLG.fsts,"$graphsscp" 

cp -a "$langdir"/* "$graphsdir"
am-info --print-args=false "$modeldir/final.mdl" |\
 grep pdfs | awk '{print $NF}' > "$graphsdir/num_pdfs"

# Creates the graph table.
#fstcopy "scp:$graphsdir/HCLG.fsts.scp" "ark,scp:$graphsdir/HCLG.fsts,$graphsdir/tmp.HCLG.fsts.scp"
#mv "$graphsdir/tmp.HCLG.fsts.scp" "$graphsdir/HCLG.fsts.scp"

#Cleanup the separate graph directories:
rm -rf "$graphsdir"/TMP_*