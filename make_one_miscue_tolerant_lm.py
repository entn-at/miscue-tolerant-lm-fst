#!/usr/bin/env python

from __future__ import print_function
import prompt_lmfst
import argparse

parser = argparse.ArgumentParser(description="""
        This script creates a reading miscue tolerant language model,
        which is suitable for decoding read prompts.
        It reads a line of text from the standard input and writes a
        text-form WFST that models reading errors into the standard
        output, ready for fstcompile from openfst.""")

# The weights dict defines relative probabilities of transitions.
# They are normalised at each state so that the probabilites sum to one.
# Not all transitions are possible at every step, and this way we can
# ensure that the FST stays stochastic.
# It may also be more intuitive to define the weights as 10:1, instead of
# 0.9091:0.0909 (the true probabilities).
# In the resulting FST these are converted to OpenFst weights, in the log semiring.
# In that semiring the weight (==the cost) of a transition is a
# negative logarithm of the probability.
weights = {
        "Correct":      100,    #The correct next word
        "Rubbish":      5,      #Speech-like noises, hesitations, etc.
        "Skip":         10,     #Jump forward one word
        "Repeat":       30,     #Jump backward one word
        "JumpForward":  5,      #Jump forward multiple words
        "JumpBackward": 5,      #Jump backward multiple words
        "Truncation":   5,      #An incomplete pronounciation
        "PrematureEnd": 3,      #Unexpected end of utterance
        "FinalState":   0.0     #NOTE: This is an actual weight!
                                # For interface simplicity, it is kept in the same dict.
}

# The special_labels dict defines non-word labels which are used for
# the miscue paths. Not all need specific labels, but some do.
special_labels = {
        "Epsilon":      "<eps>"
        "Rubbish":      "[RUB]",
        "Skip":         "[SKP]",
}


## The next functions define recipes for adding the different types of paths
## to the FST.
## The idea is to always consume a label if possible and design the recipes so that they
## don't add multiple arcs with the same input label from any state.
## This way we get a fast, deterministic FST.

def addCorrectPaths(p_fst, weights):
    for word in p_fst.words:
        p_fst.addArc(word.start, word.final, word.label, word.label, weights["Correct"])
    p_fst.addFinalState(p_fst.words[-1].final, weights["FinalState"])

def addRubbishPaths(p_fst, weights):
    for word in p_fst.words:
        p_fst.addArc(word.start, word.start,
            special_labels["Rubbish"], special_labels["Rubbish"],
            weights["Rubbish"])
    p_fst.addArc(p_fst.words[-1].final, p_fst.words[-1].final,
            special_labels["Rubbish"], special_labels["Rubbish"],
            weights["Rubbish"])

def addSkipPaths(p_fst, weights):
    # This will loop over all but the last word.
    for word, next_word in zip(p_fst.words, p_fst.words[1:]):
        # Don't add skip if a word is repeated.
        # This way, skips are always notated at the end of a sequence of repeated words.
        if word.label != next_word.label:
            skip_state = p_fst.newState()
            p_fst.addArc(word.start, skip_state,
                    next_word.label, special_labels["Skip"],
                    weights["Skip"])
            p_fst.addArc(skip_state, next_word.final,
                    special_labels["Epsilon"], next_word.label,
                    weights["Correct"])
    # Then the last word.
    p_fst.addArc(p_fst.words[-1].start, p_fst.words[-1].final,
            special_labels["Epsilon"], special_labels["Skip"],
            weights["Skip"])

def addRepeatPaths(p_fst, weights):
    # This will loop over all but the last word:
    for word, next_word in zip(p_fst.words, p_fst.words[1:]):
        # Don't add repeat if a word is repeated in the correct sequence.
        # This way, repeats are always notated at the end of a sequence of repeated words.
        if word.label != next_word.label:
            p_fst.addArc(word.final, word.final,
                    word.label, word.label,
                    weights["Repeat"])
    # Then the last word:
    p_fst.addArc(p_fst.words[-1].final, p_fst.words[-1].final,
            p_fst.words[-1].label, p_fst.words[-1].label,
            weights["Repeat"])







fst = prompt_lmfst.PromptLMFST()