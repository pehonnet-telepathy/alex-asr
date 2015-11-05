# encoding: utf-8
# distutils: language = c++
from __future__ import unicode_literals

from cython cimport address
from libc.stdlib cimport malloc, free
from libcpp.vector cimport vector
from libcpp cimport bool
from libcpp.string cimport string
cimport fst._fst
cimport fst.libfst
import fst
from kaldi2.utils import lattice_to_nbest



cdef extern from "pykaldi2_decoder/pykaldi2_decoder.h" namespace "kaldi":
    cdef cppclass PyKaldi2Decoder:
        PyKaldi2Decoder(string model_path) except +
        size_t Decode(int max_frames) except +
        void FrameIn(unsigned char *frame, size_t frame_len) except +
        bool GetBestPath(vector[int] *v_out, float *lik) except +
        bool GetLattice(fst.libfst.LogVectorFst *fst_out, double *tot_lik) except +
        string GetWord(int word_id) except +
        void InputFinished() except +
        bool EndpointDetected() except +
        void FinalizeDecoding() except +
        void Reset() except +


cdef class cPyKaldi2Decoder:

    """
    Python wrapper around C++ Kaldi PyKaldi2Decoder
    which provides on-line speech recognition interface
    """

    cdef PyKaldi2Decoder * thisptr
    cdef long fs
    cdef int nchan, bits
    cdef utt_decoded

    def __init__(self, model_path, fs=16000, nchan=1, bits=16):
        """ __init__(self, fs=16000, nchan=1, bits=16)
        
        Initialise recognizer with audio input stream parameters.
        """
        self.thisptr = new PyKaldi2Decoder(model_path)
        self.utt_decoded = 0
        self.fs, self.nchan, self.bits = fs, nchan, bits
        assert(self.bits % 8 == 0)

    def __dealloc__(self):
        del self.thisptr

    def decode(self, max_frames=10):
        """decode(self, max_frames)

        Decodes at maximum max_frames.
        Return number of actually decoded frames in range [0, max_frames].
        The decoding has RTF < 1.0 on common computer.
        Consequently, for frames shift 10 ms the decoding
        should be faster than 0.01 * max_frames seconds."""
        new_dec = self.thisptr.Decode(max_frames)
        self.utt_decoded += new_dec
        return new_dec

    def frame_in(self, bytes frame_str):
        """frame_in(self, bytes frame_str, int num_samples)

        Accepts input raw audio data and interpret them
        according sample width (self.bits) settings"""
        num_bytes = (self.bits / 8)
        num_samples = len(frame_str) / num_bytes
        assert(num_samples * num_bytes == len(frame_str)), "Not align audio to for %d bits" % self.bits
        self.thisptr.FrameIn(frame_str, num_samples)

    def get_best_path(self):
        """get_best_path(self)

        Returns one-best ASR hypothesis
        directly from internal representation."""
        cdef vector[int] t
        cdef float lik
        self.thisptr.GetBestPath(address(t), address(lik))
        words = [t[i] for i in xrange(t.size())]
        return (lik, words)

    def get_nbest(self, n=1):
        """get_nbest(self, n=1)

        Returns n-best list extracted from word posterior lattice."""
        lik, lat = self.get_lattice()
        return lattice_to_nbest(lat, n)

    def get_lattice(self):
        """get_lattice(self)

        Return word posterior lattice and its likelihood.
        It may last non-trivial amount of time e.g. 100 ms."""
        cdef double lik = -1
        r = fst.LogVectorFst()
        if self.utt_decoded > 0:
            self.thisptr.GetLattice((<fst._fst.LogVectorFst?>r).fst, address(lik))
        self.utt_decoded = 0
        return (lik, r)

    def get_word(self, word_id):
        return self.thisptr.GetWord(word_id)

    def endpoint_detected(self):
        return self.thisptr.EndpointDetected()

    def input_finished(self):
        self.thisptr.InputFinished()

    def finalize_decoding(self):
        """FinalizeDecoding(self)

        It prepares internal representation for lattice extration."""
        self.thisptr.FinalizeDecoding()

    def reset(self):
        """reset(self, keep_buffer_data)

        Resets the frame counter and prepare decoder for new utterance.
        Dependently on reset_pipeline parameter the data are 
        buffered data are cleared in the pipeline.
        If the (audio) data are kept they are the first input 
        data for new utterance."""
        self.thisptr.Reset()
