!{\src2tex{textfont=tt}}
!!****f* ABINIT/make_efg_el
!! NAME
!! make_efg_el
!!
!! FUNCTION
!! compute the electric field gradient due to electron density
!!
!! COPYRIGHT
!! Copyright (C) 2005-2017 ABINIT group (JJ)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~ABINIT/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!!
!! INPUTS
!! mpi_enreg=information about MPI parallelization
!! natom, number of atoms in unit cell
!! nfft,ngfft(18), number of FFT points and details of FFT
!! nspden, number of spin components
!! nsym=number of symmetries in space group
!! rhor(nfft,nspden), valence electron density, here $\tilde{n} + \hat{n}$
!! rprimd(3,3), conversion from crystal coordinates to cartesian coordinates
!! symrel(3,3,nsym)=symmetry operators in terms of action on primitive translations
!! tnons(3,nsym) = nonsymmorphic translations
!! xred(3,natom), location of atoms in crystal coordinates.
!!
!! OUTPUT
!! efg(3,3,natom), the 3x3 efg tensor at each atomic site due to rhor
!!
!! NOTES
!! This routine computes the electric field gradient, specifically the components
!! $\partial^2 V/\partial x_\alpha \partial x_\beta$ of the potential generated by the valence 
!! electrons, at each atomic site in the unit cell. Key references: Kresse and Joubert, ``From
!! ultrasoft pseudopotentials to the projector augmented wave method'', Phys. Rev. B. 59, 1758--1775 (1999),
!! and Profeta, Mauri, and Pickard, ``Accurate first principles prediction of $^{17}$O NMR parameters in
!! SiO$_2$: Assignment of the zeolite ferrierite spectrum'', J. Am. Chem. Soc. 125, 541--548 (2003). This 
!! routine computes the second derivatives of the potential generated by $\tilde{n}$ (see Kresse and Joubert
!! for notation, Fourier-transforming the density, doing the sum in G space, and then transforming back at
!! each atomic site. The final formula is
!! \begin{displaymath}
!! \frac{\partial^2 V}{\partial x_\alpha\partial x_\beta} = -4\pi^2\sum_G (G_\alpha G_\beta - \delta_{\alpha,\beta}G^2/3) 
!! \left(\frac{\tilde{n}(G)}{\pi G^2}\right)e^{2\pi i G\cdot R}
!! \end{displaymath}
!! 
!!
!! PARENTS
!!      calc_efg
!!
!! CHILDREN
!!      fourdp,matpointsym,matr3inv,ptabs_fourdp,xmpi_sum,xred2xcart
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif
#include "abi_common.h"

subroutine make_efg_el(efg,mpi_enreg,natom,nfft,ngfft,nspden,nsym,paral_kgb,rhor,rprimd,symrel,tnons,xred)

 use defs_basis
 use defs_abitypes
 use m_profiling_abi
 use m_mpinfo,   only : ptabs_fourdp
 use m_xmpi,     only : xmpi_sum

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'make_efg_el'
 use interfaces_32_util
 use interfaces_41_geometry
 use interfaces_45_geomoptim
 use interfaces_53_ffts
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 integer,intent(in) :: natom,nfft,nspden,nsym,paral_kgb
 type(MPI_type),intent(in) :: mpi_enreg
!arrays
 integer,intent(in) :: ngfft(18),symrel(3,3,nsym)
 real(dp),intent(in) :: rhor(nfft,nspden),rprimd(3,3),tnons(3,nsym),xred(3,natom)
 real(dp),intent(out) :: efg(3,3,natom)

!Local variables-------------------------------
!scalars
 integer :: cplex,fftdir,fofg_index,iatom,i1,i2,i2_local,i23,i3,id1,id2,id3
 integer :: ierr,ig,ig2,ig3,ii,ii1,ing,jj
 integer :: me_fft,n1,n2,n3,nproc_fft,tim_fourdp
 real(dp) :: cph,derivs,phase,sph,trace
! type(MPI_type) :: mpi_enreg_seq
!arrays
 integer :: id(3)
 integer, ABI_CONTIGUOUS pointer :: fftn2_distrib(:),ffti2_local(:)
 integer, ABI_CONTIGUOUS pointer :: fftn3_distrib(:),ffti3_local(:)
 real(dp) :: gprimd(3,3),gred(3),gvec(3),ratom(3)
 real(dp),allocatable :: fofg(:,:),fofr(:),gq(:,:),xcart(:,:)

! ************************************************************************

!DEBUG
!write(std_out,*)' make_efg_el : enter'
!ENDDEBUG

 ABI_ALLOCATE(fofg,(2,nfft))
 ABI_ALLOCATE(fofr,(nfft))
 ABI_ALLOCATE(xcart,(3,natom))

 efg(:,:,:) = zero
 call xred2xcart(natom,rprimd,xcart,xred) ! get atomic locations in cartesian coords
 call matr3inv(rprimd,gprimd)

 tim_fourdp = 0 ! timing code, not using
 fftdir = -1 ! FT from R to G
 cplex = 1 ! fofr is real
!here we are only interested in the total charge density including nhat, which is rhor(:,1)
!regardless of the value of nspden. This may change in the future depending on 
!developments with noncollinear magnetization and so forth. Such a change will
!require an additional loop over nspden.
!Multiply by -1 to convert the electron particle density to the charge density
 fofr(:) = -rhor(:,1)

 ! Get the distrib associated with this fft_grid  See hartre.F90 for another example where
 ! this is done
 n1=ngfft(1); n2=ngfft(2); n3=ngfft(3)
 nproc_fft = mpi_enreg%nproc_fft; me_fft = mpi_enreg%me_fft
 call ptabs_fourdp(mpi_enreg,n2,n3,fftn2_distrib,ffti2_local,fftn3_distrib,ffti3_local)

 call fourdp(cplex,fofg,fofr,fftdir,mpi_enreg,nfft,ngfft,paral_kgb,tim_fourdp) ! construct charge density in G space

 ! the following loops over G vectors has been copied from hartre.F90 in order to be compatible with
 ! possible FFT parallelism

 ! In order to speed the routine, precompute the components of g
 ! Also check if the booked space was large enough...
 ABI_ALLOCATE(gq,(3,max(n1,n2,n3)))
 do ii=1,3
   id(ii)=ngfft(ii)/2+2
   do ing=1,ngfft(ii)
     ig=ing-(ing/id(ii))*ngfft(ii)-1
     gq(ii,ing)=ig
   end do
 end do
 id1=n1/2+2;id2=n2/2+2;id3=n3/2+2

 ! Triple loop on each dimension
 do i3=1,n3
   ig3=i3-(i3/id3)*n3-1
   gred(3) = gq(3,i3)

   do i2=1,n2
     ig2=i2-(i2/id2)*n2-1
     if (fftn2_distrib(i2) == me_fft) then

       gred(2) = gq(2,i2)
       i2_local = ffti2_local(i2)
       i23=n1*(i2_local-1 +(n2/nproc_fft)*(i3-1))
       ! Do the test that eliminates the Gamma point outside of the inner loop
       ii1=1
       if(i23==0 .and. ig2==0 .and. ig3==0) ii1=2

       ! Final inner loop on the first dimension (note the lower limit)
       do i1=ii1,n1
!         gs=gs2+ gq(1,i1)*(gq(1,i1)*gmet(1,1)+gqg2p3)
         gred(1) = gq(1,i1)
         gvec(1:3) = MATMUL(gprimd,gred)
         fofg_index=i1+i23
         trace = dot_product(gvec,gvec)
         do ii = 1, 3 ! sum over components of efg tensor
           do jj = 1, 3 ! sum over components of efg tensor
             derivs = gvec(ii)*gvec(jj) ! This term is $G_\alpha G_\beta$
             if (ii == jj) derivs = derivs - trace/three
             do iatom = 1, natom ! sum over atoms in unit cell
               ratom(:) = xcart(:,iatom) ! extract location of atom iatom
               phase = two_pi*dot_product(gvec,ratom) ! argument of $e^{2\pi i G\cdot R}$
               cph = cos(phase)
               sph = sin(phase)
               efg(ii,jj,iatom) = efg(ii,jj,iatom) - &
&               four_pi*derivs*(fofg(1,fofg_index)*cph-fofg(2,fofg_index)*sph)/trace ! real part of efg tensor
             end do ! end loop over atoms in cell
           end do ! end loop over jj in V_ij
         end do ! end loop over ii in V_ij
       end do ! End loop on i1
     end if
   end do ! End loop on i2
 end do ! End loop on i3

 call xmpi_sum(efg,mpi_enreg%comm_fft,ierr)

! symmetrize tensor at each atomic site using point symmetry operations
 do iatom = 1, natom
   call matpointsym(iatom,efg(:,:,iatom),natom,nsym,rprimd,symrel,tnons,xred)
 end do

 ABI_DEALLOCATE(fofg)
 ABI_DEALLOCATE(fofr)
 ABI_DEALLOCATE(xcart)
 ABI_DEALLOCATE(gq)

!DEBUG
!write(std_out,*)' make_efg_el : exit '
!stop
!ENDDEBUG

end subroutine make_efg_el
!!***
