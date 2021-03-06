!{\src2tex{textfont=tt}}
!!****m* ABINIT/m_scf_history
!! NAME
!!  m_scf_history
!!
!! FUNCTION
!!  This module provides the definition of the scf_history_type used to store
!!  various arrays obtained from previous SCF cycles (density, positions...).
!!
!! COPYRIGHT
!! Copyright (C) 2011-2017 ABINIT group (MT)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!!
!! INPUTS
!!
!! OUTPUT
!!
!! PARENTS
!!
!! CHILDREN
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

MODULE m_scf_history

 use defs_basis
 use defs_abitypes
 use m_profiling_abi
 use m_errors

 use m_pawcprj,  only : pawcprj_type, pawcprj_free
 use m_pawrhoij, only : pawrhoij_type, pawrhoij_nullify, pawrhoij_free

 implicit none

 private

! public procedures.
 public :: scf_history_init
 public :: scf_history_free
 public :: scf_history_nullify
!!***

!!****t* m_scf_history/scf_history_type
!! NAME
!! scf_history_type
!!
!! FUNCTION
!! This structured datatype contains various arrays obtained from
!! previous SCF cycles (density, positions...)
!!
!! SOURCE

 type, public :: scf_history_type

! WARNING : if you modify this datatype, please check whether there might be creation/destruction/copy routines,
! declared in another part of ABINIT, that might need to take into account your modification.

! Integer scalar

  integer :: history_size
   ! Number of previous SCF cycles stored in history
   ! If history_size<0, scf_history is not used
   ! If history_size=0, scf_history only contains
   !    current values of data (rhor, taur, pawrhoih, xred)
   ! If history_size>0, scf_history contains
   !    current values of data and also
   !    history_size previous values of these data

  integer :: icall
   ! Number of call for the routine extraprho

  integer :: mcg
   ! Size of cg array

  integer :: mcprj
   ! Size of cprj datsatructure array

  integer :: natom
   ! Number of atoms in cell

  integer :: nfft
   ! Size of FFT grid (for density)

  integer :: nspden
   ! Number of independant spin components for density

  integer :: usecg
   ! usecg=1 if the extrapolation of the wavefunctions is active

  real(dp) :: alpha
   ! alpha mixing coefficient for the prediction of density and wavefunctions

  real(dp) :: beta
   ! beta mixing coefficient for the prediction of density and wavefunctions

! Integer arrays

  integer,allocatable :: hindex(:)
   ! hindex(history_size)
   ! Indexes of SCF cycles in the history
   ! hindex(1) is the newest SCF cycle
   ! hindex(history_size) is the oldest SCF cycle

! Real (real(dp)) arrays

   real(dp),allocatable :: cg(:,:,:)
    ! cg(2,mcg,history_size)
    ! wavefunction coefficients needed for each SCF cycle of history

   real(dp),allocatable :: deltarhor(:,:,:)
    ! deltarhor(nfft,nspden,history_size)
    ! Diference between electronic density (in real space)
    ! and sum of atomic densities at the end of each SCF cycle of history

   real(dp),allocatable :: atmrho_last(:)
    ! atmrho_last(nfft)
    ! Sum of atomic densities at the end of the LAST SCF cycle

   real(dp),allocatable :: rhor_last(:,:)
    ! rhor_last(nfft,nspden)
    ! Last computed electronic density (in real space)

   real(dp),allocatable :: taur_last(:,:)
    ! taur_last(nfft,nspden*usekden)
    ! Last computed kinetic energy density (in real space)

   real(dp),allocatable :: xreddiff(:,:,:)
    ! xreddiff(3,natom,history_size)
    ! Difference of reduced coordinates of atoms between a
    ! SCF cycle and the previous

   real(dp),allocatable :: xred_last(:,:)
    ! xred_last(3,natom)
    ! Last computed atomic positions (reduced coordinates)

! Structured datatypes arrays

  type(pawrhoij_type), allocatable :: pawrhoij(:,:)
    ! pawrhoij(natom,history_size)
    ! PAW only: occupancies matrix at the end of each SCF cycle of history

  type(pawrhoij_type), allocatable :: pawrhoij_last(:)
    ! pawrhoij_last(natom)
    ! PAW only: last computed occupancies matrix

  type(pawcprj_type),allocatable :: cprj(:,:,:)
    !cprj(natom,nspinor*mband*mkmem*nsppol,history_size)

 end type scf_history_type
!!***

CONTAINS !===========================================================
!!***

!!****f* m_scf_history/scf_history_init
!! NAME
!!  scf_history_init
!!
!! FUNCTION
!!  Init all scalars and pointers in a scf_history datastructure
!!  according to scf_history%history_size value which has to be
!!  defined before calling this routine
!!
!! INPUTS
!!  dtset <type(dataset_type)>=all input variables in this dataset
!!  mpi_enreg=MPI-parallelisation information
!!
!! SIDE EFFECTS
!!  scf_history=<type(scf_history_type)>=scf_history datastructure
!!
!! PARENTS
!!      gstate
!!
!! CHILDREN
!!
!! SOURCE

subroutine scf_history_init(dtset,mpi_enreg,scf_history)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'scf_history_init'
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 type(dataset_type),intent(in) :: dtset
 type(MPI_type),intent(in) :: mpi_enreg
!arrays
 type(scf_history_type),intent(inout) :: scf_history

!Local variables-------------------------------
!scalars
 integer :: jj,mband_cprj,my_natom,my_nspinor,nfft
!arrays

!************************************************************************

 !@scf_history_type

 if (scf_history%history_size<0) then
   call scf_history_nullify(scf_history)
 else

   nfft=dtset%nfft
   if (dtset%usepaw==1.and.(dtset%pawecutdg>=1.0000001_dp*dtset%ecut)) nfft=dtset%nfftdg
   my_natom=mpi_enreg%my_natom

   if (scf_history%history_size>=0) then
     ABI_ALLOCATE(scf_history%rhor_last,(nfft,dtset%nspden))
     ABI_ALLOCATE(scf_history%taur_last,(nfft,dtset%nspden*dtset%usekden))
     ABI_ALLOCATE(scf_history%xred_last,(3,dtset%natom))
     ABI_DATATYPE_ALLOCATE(scf_history%pawrhoij_last,(my_natom*dtset%usepaw))
     if (dtset%usepaw==1) then
       call pawrhoij_nullify(scf_history%pawrhoij_last)
     end if
   end if

   if (scf_history%history_size>0) then

     scf_history%natom=dtset%natom
     scf_history%nfft=nfft
     scf_history%nspden=dtset%nspden
     scf_history%alpha=zero
     scf_history%beta=zero
     scf_history%icall=0

     scf_history%usecg=0
     scf_history%mcg=0
     scf_history%mcprj=0
     if (dtset%extrapwf>0) then
       scf_history%usecg=1
       my_nspinor=max(1,dtset%nspinor/mpi_enreg%nproc_spinor)
       scf_history%mcg=dtset%mpw*my_nspinor*dtset%mband*dtset%mkmem*dtset%nsppol
       if (dtset%usepaw==1) then
         mband_cprj=dtset%mband
         if (dtset%paral_kgb/=0) mband_cprj=mband_cprj/mpi_enreg%nproc_band
         scf_history%mcprj=my_nspinor*mband_cprj*dtset%mkmem*dtset%nsppol
       end if
     end if

     ABI_ALLOCATE(scf_history%hindex,(scf_history%history_size))
     scf_history%hindex(:)=0
     ABI_ALLOCATE(scf_history%deltarhor,(nfft,dtset%nspden,scf_history%history_size))
     ABI_ALLOCATE(scf_history%xreddiff,(3,dtset%natom,scf_history%history_size))
     ABI_ALLOCATE(scf_history%atmrho_last,(nfft))

     if (dtset%usepaw==1) then
       ABI_DATATYPE_ALLOCATE(scf_history%pawrhoij,(my_natom,scf_history%history_size))
       do jj=1,scf_history%history_size
         call pawrhoij_nullify(scf_history%pawrhoij(:,jj))
       end do
     end if

     if (scf_history%usecg==1) then
       ABI_ALLOCATE(scf_history%cg,(2,scf_history%mcg,scf_history%history_size))
       if (dtset%usepaw==1) then
         ABI_DATATYPE_ALLOCATE(scf_history%cprj,(dtset%natom,scf_history%mcprj,scf_history%history_size))
       end if
     end if

   end if
 end if

end subroutine scf_history_init
!!***

!----------------------------------------------------------------------

!!****f* m_scf_history/scf_history_free
!! NAME
!!  scf_history_free
!!
!! FUNCTION
!!  Clean and destroy a scf_history datastructure
!!
!! SIDE EFFECTS
!!  scf_history(:)=<type(scf_history_type)>=scf_history datastructure
!!
!! PARENTS
!!      gstateimg
!!
!! CHILDREN
!!
!! SOURCE

subroutine scf_history_free(scf_history)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'scf_history_free'
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!arrays
 type(scf_history_type),intent(inout) :: scf_history

!Local variables-------------------------------
!scalars
 integer :: jj

!************************************************************************

 !@scf_history_type

 if (allocated(scf_history%pawrhoij_last)) then
   call pawrhoij_free(scf_history%pawrhoij_last)
   ABI_DATATYPE_DEALLOCATE(scf_history%pawrhoij_last)
 end if
 if (allocated(scf_history%pawrhoij)) then
   do jj=1,size(scf_history%pawrhoij,2)
     call pawrhoij_free(scf_history%pawrhoij(:,jj))
   end do
   ABI_DATATYPE_DEALLOCATE(scf_history%pawrhoij)
 end if
 if (allocated(scf_history%cprj)) then
   do jj=1,size(scf_history%cprj,3)
     call pawcprj_free(scf_history%cprj(:,:,jj))
   end do
   ABI_DATATYPE_DEALLOCATE(scf_history%cprj)
 end if

 if (allocated(scf_history%hindex))       then
   ABI_DEALLOCATE(scf_history%hindex)
 end if
 if (allocated(scf_history%deltarhor))    then
   ABI_DEALLOCATE(scf_history%deltarhor)
 end if
 if (allocated(scf_history%xreddiff))     then
   ABI_DEALLOCATE(scf_history%xreddiff)
 end if
 if (allocated(scf_history%atmrho_last))  then
   ABI_DEALLOCATE(scf_history%atmrho_last)
 end if
 if (allocated(scf_history%xred_last))    then
   ABI_DEALLOCATE(scf_history%xred_last)
 end if
 if (allocated(scf_history%rhor_last))    then
   ABI_DEALLOCATE(scf_history%rhor_last)
 end if
 if (allocated(scf_history%taur_last))    then
   ABI_DEALLOCATE(scf_history%taur_last)
 end if
 if (allocated(scf_history%cg))           then
   ABI_DEALLOCATE(scf_history%cg)
 end if

 scf_history%history_size=-1
 scf_history%usecg=0
 scf_history%icall=0
 scf_history%mcprj=0
 scf_history%mcg=0

end subroutine scf_history_free
!!***

!----------------------------------------------------------------------

!!****f* m_scf_history/scf_history_nullify
!! NAME
!!  scf_history_nullify
!!
!! FUNCTION
!!  Nullify (set to null) an scf_history datastructure
!!
!! SIDE EFFECTS
!!  scf_history(:)=<type(scf_history_type)>=scf_history datastructure
!!
!! PARENTS
!!      gstateimg,m_scf_history
!!
!! CHILDREN
!!
!! SOURCE

subroutine scf_history_nullify(scf_history)


!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'scf_history_nullify'
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!arrays
 type(scf_history_type),intent(inout) :: scf_history
!Local variables-------------------------------
!scalars

!************************************************************************

 !@scf_history_type
 scf_history%history_size=-1
 scf_history%usecg=0
 scf_history%icall=0
 scf_history%mcprj=0
 scf_history%mcg=0

end subroutine scf_history_nullify
!!***

END MODULE m_scf_history
!!***
