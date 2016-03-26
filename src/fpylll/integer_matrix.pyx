# -*- coding: utf-8 -*-
include "config.pxi"
include "cysignals/signals.pxi"

"""
Integer matrices.

.. moduleauthor:: Martin R. Albrecht <martinralbrecht+fpylll@googlemail.com>
"""

include "cysignals/signals.pxi"

from cpython cimport PyIndex_Check
from fplll cimport MatrixRow, sqrNorm, Z_NR
from fpylll.util cimport preprocess_indices
from fpylll.io cimport assign_Z_NR_mpz, assign_mpz, mpz_get_python

import re
from math import log, ceil, sqrt

from gmp.mpz cimport mpz_init, mpz_mod, mpz_fdiv_q_ui, mpz_clear, mpz_cmp, mpz_sub, mpz_set


cdef class IntegerMatrixRow:
    """
    A reference to a row in an integer matrix.
    """
    def __init__(self, IntegerMatrix M, int row):
        """Create a row reference.

        :param IntegerMatrix M: Integer matrix
        :param int row: row index

        Row references are immutable::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(2, 3)
            >>> A[0,0] = 1; A[0,1] = 2; A[0,2] = 3
            >>> r = A[0]
            >>> r[0]
            1
            >>> r[0] = 1
            Traceback (most recent call last):
            ...
            TypeError: 'fpylll.integer_matrix.IntegerMatrixRow' object does not support item assignment

        """
        preprocess_indices(row, row, M.nrows, M.nrows)
        self.row = row
        self.m = M

    def __getitem__(self, int column):
        """Return entry at ``column``

        :param int column: integer offset

        """
        preprocess_indices(column, column, self.m._core.getCols(), self.m._core.getCols())
        r = mpz_get_python(self.m._core[0][self.row][column].getData())
        return r

    def __str__(self):
        """String representation of this row.
        """
        cdef int i
        r = []
        for i in range(self.m._core.getCols()):
            t = mpz_get_python(self.m._core[0][self.row][i].getData())
            r.append(str(t))
        return "(" + ", ".join(r) + ")"

    def __repr__(self):
        return "row %d of %r"%(self.row, self.m)


    def __abs__(self):
        """Return ℓ_2 norm of this vector.

        >>> A = IntegerMatrix.from_iterable(1, 3, [1,2,3])
        >>> A[0].norm()  # doctest: +ELLIPSIS
        3.74165...
        >>> 1*1 + 2*2 + 3*3
        14
        >>> from math import sqrt
        >>> sqrt(14)  # doctest: +ELLIPSIS
        3.74165...

        """
        cdef Z_NR[mpz_t] t
        sqrNorm[Z_NR[mpz_t]](t, self.m._core[0][self.row], self.m._core.getCols())
        # TODO: don't just use doubles
        return sqrt(t.get_d())

    norm = __abs__

cdef class IntegerMatrix:
    """
    Dense matrices over the Integers.
    """
    def __init__(self, arg0, arg1=None):
        """Construct a new integer matrix

        :param int arg0: number of rows ≥ 0 or matrix
        :param int arg1: number of columns ≥ 0 or ``None``

        The default constructor takes the number of rows and columns::

            >>> from fpylll import IntegerMatrix
            >>> IntegerMatrix(10, 10) # doctest: +ELLIPSIS
            <IntegerMatrix(10, 10) at 0x...>

            >>> IntegerMatrix(10, 0) # doctest: +ELLIPSIS
            <IntegerMatrix(10, 0) at 0x...>

            >>> IntegerMatrix(-1,  0)
            Traceback (most recent call last):
            ...
            ValueError: Number of rows must be >0

        The default constructor is also a copy constructor::

            >>> A = IntegerMatrix(2, 2)
            >>> A[0,0] = 1
            >>> B = IntegerMatrix(A)
            >>> B[0,0]
            1
            >>> A[0,0] = 2
            >>> B[0,0]
            1

        """
        cdef int i, j

        if PyIndex_Check(arg0) and PyIndex_Check(arg1):
            if arg0 < 0:
                raise ValueError("Number of rows must be >0")

            if arg1 < 0:
                raise ValueError("Number of columns must be >0")

            self._core = new ZZ_mat[mpz_t](arg0, arg1)
            return

        elif isinstance(arg0, IntegerMatrix) and arg1 is None:
            self._core = new ZZ_mat[mpz_t](arg0.nrows, arg0.ncols)
            for i in range(self.nrows):
                for j in range(self.ncols):
                    self._core[0][i][j] = (<IntegerMatrix>arg0)._core[0][i][j]
            return

        else:
            raise TypeError("Parameters arg0 and arg1 not understood")

    def set_matrix(self, A):
        """Set this matrix from matrix-like object A

        :param A: a matrix like object, with element access A[i,j] or A[i][j]

        .. note:: entries starting at ``A[nrows, ncols]`` are ignored.

        """
        cdef int i, j
        cdef int m = self.nrows
        cdef int n = self.ncols

        try:
            for i in range(m):
                for j in range(n):
                    self[i, j] = A[i, j]
        except TypeError:
            for i in range(m):
                for j in range(n):
                    self[i, j] = A[i][j]


    def set_iterable(self, A):
        """Set this matrix from iterable A

        :param A: an iterable object such as a list or tuple

        .. note:: entries starting at ``A[nrows * ncols]`` are ignored.

        """
        cdef int i, j
        cdef int m = self.nrows
        cdef int n = self.ncols
        it = iter(A)

        for i in range(m):
            for j in range(n):
                self[i, j] = next(it)


    def to_matrix(self, A):
        """Write this matrix to matrix-like object A

        :param A: a matrix like object, with element access A[i,j] or A[i][j]
        :returns: A

        """
        cdef int i, j
        cdef int m = self.nrows
        cdef int n = self.ncols

        try:
            for i in range(m):
                for j in range(n):
                    A[i, j] = self[i, j]
        except TypeError:
            for i in range(m):
                for j in range(n):
                    A[i][j] = A[i][j]
        return A

    def __dealloc__(self):
        """
        Delete integer matrix
        """
        del self._core

    def __repr__(self):
        """Short representation.

        """
        return "<IntegerMatrix(%d, %d) at %s>" % (
            self._core.getRows(),
            self._core.getCols(),
            hex(id(self)))

    def __str__(self):
        """Full string representation of this matrix.

        """
        cdef int i, j
        max_length = []
        for j in range(self._core.getCols()):
            max_length.append(1)
            for i in range(self._core.getRows()):
                value = self[i, j]
                if not value:
                    continue
                length = max(ceil(log(abs(value), 10)), 1)
                # sign
                length += int(value < 0)
                if length > max_length[j]:
                    max_length[j] = int(length)

        r = []
        for i in range(self._core.getRows()):
            r.append(["["])
            for j in range(self._core.getCols()):
                r[-1].append(("%%%dd"%max_length[j])%self[i,j])
            r[-1].append("]")
            r[-1] = " ".join(r[-1])
        r = "\n".join(r)
        return r

    def __copy__(self):
        """Copy this matrix.
        """
        cdef IntegerMatrix A = IntegerMatrix(self.nrows, self.ncols)
        cdef int i, j
        for i in range(self.nrows):
            for j in range(self.ncols):
                A._core[0][i][j] = self._core[0][i][j]
        return A

    @property
    def nrows(self):
        """Number of Rows

        :returns: number of rows

        >>> from fpylll import IntegerMatrix
        >>> IntegerMatrix(10, 10).nrows
        10

        """
        return self._core.getRows()

    @property
    def ncols(self):
        """Number of Columns

        :returns: number of columns

        >>> from fpylll import IntegerMatrix
        >>> IntegerMatrix(10, 10).ncols
        10

        """
        return self._core.getCols()

    def __getitem__(self, key):
        """Select a row or entry.

        :param key: an integer for the row, a tuple for row and column or a slice.
        :returns: a reference to a row or an integer depending on format of ``key``

        >>> from fpylll import IntegerMatrix
        >>> A = IntegerMatrix(10, 10)
        >>> A.gen_identity(10)
        >>> A[1,0]
        0

        >>> print(A[1])
        (0, 1, 0, 0, 0, 0, 0, 0, 0, 0)

        >>> print(A[0:2])
        [ 1 0 0 0 0 0 0 0 0 0 ]
        [ 0 1 0 0 0 0 0 0 0 0 ]

        """
        cdef int i = 0
        cdef int j = 0

        if isinstance(key, tuple):
            i, j = key
            preprocess_indices(i, j, self._core.getRows(), self._core.getCols())
            r = mpz_get_python(self._core[0][i][j].getData())
            return r
        elif isinstance(key, slice):
            key = range(*key.indices(self.nrows))
            return self.submatrix(key, range(self.ncols))
        elif PyIndex_Check(key):
            i = key
            preprocess_indices(i, i, self._core.getRows(), self._core.getRows())
            return IntegerMatrixRow(self, i)
        else:
            raise ValueError("Parameter '%s' not understood."%key)

    def __setitem__(self, key, value):
        """
        Assign value to index.

        :param key: a tuple of row and column indices
        :param value: an integer

        EXAMPLE::

            >>> from fpylll import IntegerMatrix
            >>> A = IntegerMatrix(10, 10)
            >>> A.gen_identity(10)
            >>> A[1,0] = 2
            >>> A[1,0]
            2

        The notation ``A[i][j]`` is not supported.  This is because ``A[i]`` returns an object
        of type ``IntegerMatrixRow`` object which is immutable by design.  This is to avoid the
        user confusing such an object with a proper vector.::

            >>> A[1][0] = 2
            Traceback (most recent call last):
            ...
            TypeError: 'fpylll.integer_matrix.IntegerMatrixRow' object does not support item assignment

        """
        cdef int i = 0
        cdef int j = 0
        cdef mpz_t tmp

        if isinstance(key, tuple):
            i, j = key
            preprocess_indices(i, j, self._core.getRows(), self._core.getCols())
            assign_Z_NR_mpz(self._core[0][i][j], value)

        elif isinstance(key, int):
            i = key
            preprocess_indices(i, i, self._core.getRows(), self._core.getRows())
            raise NotImplementedError
        else:
            raise ValueError("Parameter '%s' not understood."%key)

    def __mul__(IntegerMatrix A, IntegerMatrix B):
        """Naive matrix × matrix products.

        :param IntegerMatrix A: m × n integer matrix A
        :param IntegerMatrix B: n × k integer matrix B
        :returns: m × k integer matrix C = A × B

        >>> from fpylll import set_random_seed
        >>> set_random_seed(1337)
        >>> A = IntegerMatrix(2, 2)
        >>> A.randomize("uniform", bits=2)
        >>> print(A)
        [ 2 0 ]
        [ 1 3 ]

        >>> B = IntegerMatrix(2, 2)
        >>> B.randomize("uniform", bits=2)
        >>> print(B)
        [ 3 2 ]
        [ 3 3 ]

        >>> print(A*B)
        [  6  4 ]
        [ 12 11 ]

        >>> print(B*A)
        [ 8 6 ]
        [ 9 9 ]

        """
        if A.ncols != B.nrows:
            raise ValueError("Number of columns of A (%d) does not match number of rows of B (%d)"%(A.ncols, B.nrows))

        cdef IntegerMatrix res = IntegerMatrix(A.nrows, B.ncols)
        cdef int i, j
        cdef Z_NR[mpz_t] tmp
        for i in range(A.nrows):
            for j in range(B.ncols):
                tmp = res._core[0][i][j]
                for k in range(A.ncols):
                    tmp.addmul(A._core[0][i][k], B._core[0][k][j])
                res._core[0][i][j] = tmp
        return res

    def __mod__(IntegerMatrix self, q):
        """Return A mod q.

        :param q: a modulus > 0

        """
        A = self.__copy__()
        A.mod(q)
        return A

    def mod(IntegerMatrix self, q, int start_row=0, int start_col=0, int stop_row=-1, int stop_col=-1):
        """Apply moduluar reduction modulo `q` to this matrix.

        :param q: modulus
        :param int start_row: starting row
        :param int start_col: starting column
        :param int stop_row: last row (excluding)
        :param int stop_col: last column (excluding)

        >>> A = IntegerMatrix(2, 2)
        >>> A[0,0] = 1001
        >>> A[1,0] = 13
        >>> A[0,1] = 102
        >>> print(A)
        [ 1001 102 ]
        [   13   0 ]

        >>> A.mod(10, start_row=1, start_col=0)
        >>> print(A)
        [ 1001 102 ]
        [    3   0 ]

        >>> A.mod(10)
        >>> print(A)
        [ 1 2 ]
        [ 3 0 ]

        >>> A = IntegerMatrix(2, 2)
        >>> A[0,0] = 1001
        >>> A[1,0] = 13
        >>> A[0,1] = 102
        >>> A.mod(10, stop_row=1)
        >>> print(A)
        [  1 2 ]
        [ 13 0 ]

        """
        preprocess_indices(start_row, start_col, self.nrows, self.ncols)
        preprocess_indices(stop_row, stop_col, self.nrows+1, self.ncols+1)

        cdef mpz_t q_
        mpz_init(q_)
        try:
            assign_mpz(q_, q)
        except NotImplementedError, msg:
            mpz_clear(q_)
            raise NotImplementedError(msg)

        cdef mpz_t t1
        mpz_init(t1)
        cdef mpz_t t2
        mpz_init(t2)

        cdef mpz_t q2_
        mpz_init(q2_)
        mpz_fdiv_q_ui(q2_, q_, 2)

        cdef int i, j
        for i in range(self.nrows):
            for j in range(self.ncols):
                mpz_set(t1, self._core[0][i][j].getData())

                if start_row <= i < stop_row and start_col <= i < stop_col:
                    mpz_mod(t2, t1, q_)
                    if mpz_cmp(t2, q2_) > 0:
                        mpz_sub(t2, t2, q_)
                    self._core[0][i][j].set(t2)

        mpz_clear(q_)
        mpz_clear(q2_)
        mpz_clear(t1)
        mpz_clear(t2)

    def __richcmp__(IntegerMatrix self, IntegerMatrix other, int op):
        """Compare two matrices
        """
        cdef int i, j
        cdef Z_NR[mpz_t] a, b
        if op == 2 or op == 3:
            eq = True
            if self.nrows != other.nrows:
                eq = False
            elif self.ncols != other.ncols:
                eq = False
            for i in range(self.nrows):
                if eq is False:
                    break
                for j in range(self.ncols):
                    a = self._core[0][i][j]
                    b = other._core[0][i][j]
                    if a != b:
                        eq = False
                        break
        else:
            raise NotImplementedError("Only != and == are implemented for integer matrices.")
        if op == 2:
            return eq
        elif op == 3:
            return not eq

    def apply_transform(self, IntegerMatrix U, int start_row=0):
        """Apply transformation matrix ``U`` to this matrix starting at row ``start_row``.

        :param IntegerMatrix U: transformation matrix
        :param int start_row: start transformation in this row

        """
        cdef int i, j
        cdef mpz_t tmp
        S = self.submatrix(start_row, 0, start_row + U.nrows, self.ncols)
        cdef IntegerMatrix B = U*S
        for i in range(B.nrows):
            for j in range(B.ncols):
                tmp = B._core[0][i][j].getData()
                self._core[0][start_row+i][j].set(tmp)

    def randomize(self, algorithm, **kwds):
        """Randomize this matrix using ``algorithm``.

        :param algorithm: string, see below for choices.

        Available algorithms:

        - ``"intrel"`` - assumes `d × (d+1)` matrix and size parameter ``bits``
        - ``"simdioph"`` - assumes `d × d` matrix and size parameter ``bits`` and ``bits``
        - ``"uniform"`` - assumes parameter ``bits``
        - ``"ntrulike"`` - assumes `2d × 2d` matrix, size parameter ``bits`` and modulus ``q``
        - ``"ntrulike2"`` - assumes `2d × 2d` matrix and size parameter ``bits``
        - ``"atjai"`` - assumes `d × d` matrix and float parameter ``alpha``

        """
        if algorithm == "intrel":
            bits = int(kwds["bits"])
            sig_on()
            self._core.gen_intrel(bits)
            sig_off()

        elif algorithm == "simdioph":
            bits = int(kwds["bits"])
            bits2 = int(kwds["bits2"])
            self._core.gen_simdioph(bits, bits2)

        elif algorithm == "uniform":
            bits = int(kwds["bits"])
            sig_on()
            self._core.gen_uniform(bits)
            sig_off()

        elif algorithm == "ntrulike":
            bits = int(kwds["bits"])
            q = int(kwds["q"])
            sig_on()
            self._core.gen_ntrulike(bits, q)
            sig_off()

        elif algorithm == "ntrulike2":
            bits = int(kwds["bits"])
            q = int(kwds["q"])
            sig_on()
            self._core.gen_ntrulike2(bits, q)
            sig_off()

        elif algorithm == "atjai":
            alpha = float(kwds["alpha"])
            sig_on()
            self._core.gen_ajtai(alpha)
            sig_off()

        else:
            raise ValueError("Algorithm '%s' unknown."%algorithm)

    def gen_identity(self, int nrows):
        """Generate identity matrix.

        :param nrows: number of rows

        """
        self._core.gen_identity(nrows)

    def submatrix(self, a, b, c=None, d=None):
        """Construct a new submatrix.

        :param a: either the index of the first row or an iterable of row indices
        :param b: either the index of the first column or an iterable of column indices
        :param c: the index of first excluded row (or ``None``)
        :param d: the index of first excluded column (or ``None``)
        :returns:
        :rtype:

        We illustrate the calling conventions of this function using a 10 x 10 matrix::

            >>> from fpylll import IntegerMatrix, set_random_seed
            >>> A = IntegerMatrix(10, 10)
            >>> set_random_seed(1337)
            >>> A.randomize("ntrulike", bits=22, q=4194319)
            >>> print(A)
            [ 1 0 0 0 0  752690 1522220 2972677  890755 2612607 ]
            [ 0 1 0 0 0 1522220 2972677  890755 2612607  752690 ]
            [ 0 0 1 0 0 2972677  890755 2612607  752690 1522220 ]
            [ 0 0 0 1 0  890755 2612607  752690 1522220 2972677 ]
            [ 0 0 0 0 1 2612607  752690 1522220 2972677  890755 ]
            [ 0 0 0 0 0 4194319       0       0       0       0 ]
            [ 0 0 0 0 0       0 4194319       0       0       0 ]
            [ 0 0 0 0 0       0       0 4194319       0       0 ]
            [ 0 0 0 0 0       0       0       0 4194319       0 ]
            [ 0 0 0 0 0       0       0       0       0 4194319 ]

        We can either specify start/stop rows and columns::

            >>> print(A.submatrix(0,0,2,8))
            [ 1 0 0 0 0  752690 1522220 2972677 ]
            [ 0 1 0 0 0 1522220 2972677  890755 ]

        Or we can give lists of rows, columns explicitly::

            >>> print(A.submatrix([0,1,2],range(3,9)))
            [ 0 0  752690 1522220 2972677  890755 ]
            [ 0 0 1522220 2972677  890755 2612607 ]
            [ 0 0 2972677  890755 2612607  752690 ]

        """
        cdef int m = 0
        cdef int n = 0
        cdef int i, j, row, col

        if c is None and d is None:
            try:
                iter(a)
                rows = a
                iter(b)
                cols = b
            except TypeError:
                raise ValueError("Inputs to submatrix not understood.")
            it = iter(rows)
            try:
                while True:
                    next(it)
                    m += 1
            except StopIteration:
                pass

            it = iter(cols)
            try:
                while True:
                    next(it)
                    n += 1
            except StopIteration:
                pass

            A = IntegerMatrix(m, n)

            i = 0
            for row in iter(rows):
                j = 0
                for col in iter(cols):
                    preprocess_indices(row, col, self._core.getRows(), self._core.getCols())
                    A._core[0][i][j].set(self._core[0][row][col].getData())
                    j += 1
                i += 1
            return A
        else:
            if c < 0:
                c %= self._core.getRows()
            if d < 0:
                d %= self._core.getCols()

            preprocess_indices(a, b, self._core.getRows(), self._core.getCols())
            preprocess_indices(c, d, self._core.getRows()+1, self._core.getCols()+1)

            if c < a:
                raise ValueError("Last row (%d) < first row (%d)"%(c, a))
            if d < b:
                raise ValueError("Last column (%d) < first column (%d)"%(d, b))
            i = 0
            m = c - a
            n = d - b
            A = IntegerMatrix(m, n)
            for row in range(a, c):
                j = 0
                for col in range(b, d):
                    A._core[0][i][j].set(self._core[0][row][col].getData())
                    j += 1
                i += 1
            return A

    @classmethod
    def from_file(cls, filename):
        """Construct new matrix from file.

        :param filename: name of file to read from

        """
        A = cls(0, 0)
        with open(filename, 'r') as fh:
            for i, line in enumerate(fh.readlines()):
                line = re.match("\[+(.*) *\]+", line)
                if line is None:
                    continue
                line = line.groups()[0]
                line = line.strip()
                line = [e for e in line.split(" ") if e != '']
                values = map(int, line)
                A._core.setRows(i+1)
                A._core.setCols(len(values))
                for j, v in enumerate(values):
                    A[i, j] = values[j]
        return A


    @classmethod
    def from_matrix(cls, A, nrows=None, ncols=None):
        """Construct a new integer matrix from matrix-like object A

        :param A: a matrix like object, with element access A[i,j] or A[i][j]
        :param nrows: number of rows (optional)
        :param ncols: number of columns (optional)


        >>> A = IntegerMatrix.from_matrix([[1,2,3],[4,5,6]])
        >>> print(A)
        [ 1 2 3 ]
        [ 4 5 6 ]

        """
        cdef int i, j
        cdef int m, n

        if nrows is None:
            if hasattr(A, "nrows"):
                nrows = A.nrows
            elif hasattr(A, "__len__"):
                nrows = len(A)
            else:
                raise ValueError("Cannot determine number of rows.")
            if not PyIndex_Check(nrows):
                if callable(nrows):
                    nrows = nrows()
                else:
                    raise ValueError("Cannot determine number of rows.")

        if ncols is None:
            if hasattr(A, "ncols"):
                ncols = A.ncols
            elif hasattr(A[0], "__len__"):
                ncols = len(A[0])
            else:
                raise ValueError("Cannot determine number of rows.")
            if not PyIndex_Check(ncols):
                if callable(ncols):
                    ncols = ncols()
                else:
                    raise ValueError("Cannot determine number of rows.")

        m = nrows
        n = ncols

        B = cls(m, n)
        B.set_matrix(A)
        return B

    @classmethod
    def from_iterable(cls, nrows, ncols, it):
        """Construct a new integer matrix from matrix-like object A

        :param nrows: number of rows
        :param ncols: number of columns
        :param it: an iterable of length at least ``nrows * ncols``

        >>> A = IntegerMatrix.from_iterable(2,3, [1,2,3,4,5,6])
        >>> print(A)
        [ 1 2 3 ]
        [ 4 5 6 ]

        """
        A = cls(nrows, ncols)
        A.set_iterable(it)
        return A
