!{\src2tex{textfont=tt}}
!!****f* ABINIT/calc_sigx_me
!! NAME
!! calc_sigx_me
!!
!! FUNCTION
!! Calculate diagonal and off-diagonal matrix elements of the exchange part of the self-energy operator.
!!
!! COPYRIGHT
!! Copyright (C) 1999-2017 ABINIT group (FB, GMR, VO, LR, RWG, MG, RShaltaf)
!! This file is distributed under the terms of the
!! GNU General Public License, see ~abinit/COPYING
!! or http://www.gnu.org/copyleft/gpl.txt .
!! For the initials of contributors, see ~abinit/doc/developers/contributors.txt .
!!
!! INPUTS
!! sigmak_ibz=Index of the k-point in the IBZ.
!! minbnd, maxbnd= min and Max band index for GW correction (for this k-point)
!! Gsph_x<gsphere_t>= Info on the G-sphere used for Sigma_x
!!    %nsym=number of symmetry operations
!!    %rottb(ng,timrev,nsym)=index of (IS) G where I is the identity or the inversion
!!      operation and G is one of the ng vectors in reciprocal space
!!    %timrev=2 if time-reversal symmetry is used, 1 otherwise
!!    %gvec(3,ng)=integer coordinates of each plane wave in reciprocal space
!! ikcalc=index in the array Sigp%kptgw2bz of the k-point where GW corrections are calculated
!! Ltg_k datatype containing information on the little group
!! Kmesh <kmesh_t>
!!    %nbz=Number of points in the BZ
!!    %nibz=Number of points in IBZ
!!    %kibz(3,nibz)=k-point coordinates, irreducible Brillouin zone
!!    %kbz(3,nbz)=k-point coordinates, full Brillouin zone
!!    %ktab(nbz)= table giving for each k-point in the BZ (kBZ), the corresponding
!!    %ktabi(nbz)= for each k-point in the BZ defines whether inversion has to be considered
!!    %ktabp(nbz)= phase factor associated to tnons
!! gwx_ngfft(18)=Information about 3D FFT for the oscillator strengths, see ~abinit/doc/input_variables/vargs.htm#ngfft
!! gwx_nfftot=number of points of the FFT grid for GW wavefunctions
!! Vcp <vcoul_t datatype> containing information on the cutoff technique
!!    %vc_sqrt(npwx,nqibz)= square-root of the coulombian potential for q-points in the IBZ
!! Pawtab(Psps%ntypat) <type(pawtab_type)>=paw tabulated starting data
!! Pawang <type(pawang_type)>=paw angular mesh and related data
!! Psps <type(pseudopotential_type)>=variables related to pseudopotentials
!!    %usepaw=1 for PAW, 0 for NC pseudopotentials.
!! Qmesh <kmesh_t> : datatype gathering information of the q-mesh used
!!    %ibz=q points where $\tilde\epsilon^{-1}$ has been computed
!!    %bz(3,nqbz)=coordinates of all q-points in BZ
!! Sigp <sigparams_t> (see the definition of this structured datatype)
!! Cryst<crystal_t>=Info on unit cell and symmetries
!!    %natom=number of atoms in unit cell
!!    %ucvol=unit cell volume
!!    %nsym=number of symmetry operations
!!    %typat(natom)=type of each atom
!!  much slower but it requires less memory
!! QP_BSt<ebands_t>=Datatype gathering info on the QP energies (KS if one shot)
!!  eig(Sigp%nbnds,Kmesh%nibz,%nsppol)=KS or QP energies for k-points, bands and spin
!!  occ(Sigp%nbnds,Kmesh%nibz,nsppol)=occupation numbers, for each k point in IBZ, each band and spin
!!  Paw_pwff<pawpwff_t>=Form factor used to calculate the onsite mat. elements of a plane wave.
!!  allQP_sym(%nkibz, %nsppol)<esymm_t>=Datatype collecting data on the irreducible representations of the
!!    little group of kcalc in the KS representation as well as the symmetry of the bdgw_k states.
!! prtvol=Flags governing verbosity level.
!!
!! OUTPUT
!!  Sr%x_mat(minbnd:maxbnd,minbnd:maxbnd,%nsppol*Sigp%nsig_ab)=Matrix elements of Sigma_x.
!!
!! NOTES
!!  1) The treatment of the divergence of Gygi+Baldereschi (PRB 1986) is included.
!!
!!  2) On the symmetrization of Sigma matrix elements
!!     If  Sk = k+G0 then  M_G(k, Sq)= e^{-i( Sq+G).t} M_{ S^-1(G}   (k,q)
!!     If -Sk = k+G0 then  M_G(k,-Sq)= e^{-i(-Sq+G).t} M_{-S^-1(G)}^*(k,q)
!!
!! Notice the absence of G0 in the expression. Moreover, when we sum over the little group, it turns out
!! that there is a cancellation of the phase factor associated to the non-symmorphic operations due to a
!! similar term coming from the symmetrization of \epsilon^{-1}. Mind however that the nonsymmorphic phase
!! has to be considered when epsilon^-1 is reconstructed starting from the q-points in the IBZ.
!!
!!  3) the unitary transformation relating wavefunctions
!!     at symmetric k-points should be taken into account during the symmetrization
!!     of the oscillator matrix elements. In case of G_oW_o and GW_o calculations, however,
!!     it is possible to make an invariant by just including all the degenerate states and
!!     averaging the final results over the degenerate subset. Here we divide the states
!!     where the QP energies are required into complexes. Note however that this approach is not
!!     based on group theory, and it might lead to spurious results in case of accidental degeneracies.
!!
!! PARENTS
!!      sigma
!!
!! CHILDREN
!!      cwtime,esymm_symmetrize_mels,findqg0,get_bz_item,get_uug,gsph_fft_tabs
!!      hermitianize,littlegroup_print,paw_cross_rho_tw_g,paw_rho_tw_g
!!      paw_symcprj,pawcprj_alloc,pawcprj_copy,pawcprj_free,pawmknhat_psipsi
!!      pawpwij_free,pawpwij_init,rho_tw_g,rotate_fft_mesh,sigma_distribute_bks
!!      timab,wfd_change_ngfft,wfd_get_cprj,wfd_get_many_ur,wfd_get_ur
!!      wfd_paw_get_aeur,wfd_sym_ur,wrtout,xmpi_sum
!!
!! SOURCE

#if defined HAVE_CONFIG_H
#include "config.h"
#endif

#include "abi_common.h"

subroutine calc_sigx_me(sigmak_ibz,ikcalc,minbnd,maxbnd,Cryst,QP_BSt,Sigp,Sr,Gsph_x,Vcp,Kmesh,Qmesh,&
& Ltg_k,Pawtab,Pawang,Paw_pwff,Pawfgrtab,Paw_onsite,Psps,Wfd,Wfdf,allQP_sym,gwx_ngfft,ngfftf,&
& prtvol,pawcross,gwfockmix)

 use defs_basis
 use defs_datatypes
 use m_profiling_abi
 use m_gwdefs             
 use m_xmpi
 use m_defs_ptgroups
 use m_errors
 use m_time

 use m_blas,          only : xdotc, xgemv
 use m_numeric_tools, only : hermitianize
 use m_geometry,      only : normv
 use m_crystal,       only : crystal_t
 use m_fft_mesh,      only : rotate_FFT_mesh, cigfft 
 use m_bz_mesh,       only : kmesh_t, get_BZ_item, findqg0, littlegroup_t, littlegroup_print
 use m_gsphere,       only : gsphere_t, gsph_fft_tabs
 use m_vcoul,         only : vcoul_t
 use m_pawpwij,      only : pawpwff_t, pawpwij_t, pawpwij_init, pawpwij_free, paw_rho_tw_g, paw_cross_rho_tw_g
 use m_paw_pwaves_lmn,only : paw_pwaves_lmn_t
 use m_pawang,        only : pawang_type
 use m_pawtab,        only : pawtab_type
 use m_pawfgrtab,     only : pawfgrtab_type
 use m_pawcprj,       only : pawcprj_type, pawcprj_alloc, pawcprj_free, pawcprj_copy, paw_overlap
 use m_wfd,           only : wfd_t, wfd_get_ur, wfd_get_cprj, wfd_change_ngfft, wfd_paw_get_aeur, wfd_get_many_ur,&
&                            wfd_sym_ur
 use m_sigma,         only : sigma_t
 use m_oscillators,   only : rho_tw_g, get_uug
 use m_esymm,         only : esymm_t, esymm_symmetrize_mels, esymm_failed
 use m_ptgroups,      only : sum_irreps

!This section has been created automatically by the script Abilint (TD).
!Do not modify the following lines by hand.
#undef ABI_FUNC
#define ABI_FUNC 'calc_sigx_me'
 use interfaces_14_hidewrite
 use interfaces_18_timing
 use interfaces_65_paw
 use interfaces_70_gw, except_this_one => calc_sigx_me
!End of the abilint section

 implicit none

!Arguments ------------------------------------
!scalars
 integer,intent(in) :: sigmak_ibz,ikcalc,prtvol,minbnd,maxbnd,pawcross
 real(dp), intent(in) :: gwfockmix
 type(crystal_t),intent(in) :: Cryst
 type(ebands_t),target,intent(in) :: QP_BSt
 type(kmesh_t),intent(in) :: Kmesh,Qmesh
 type(vcoul_t),intent(in) :: Vcp
 type(gsphere_t),intent(in) :: Gsph_x
 type(littlegroup_t),intent(in) :: Ltg_k
 type(Pseudopotential_type),intent(in) :: Psps
 type(sigparams_t),target,intent(in) :: Sigp
 type(sigma_t),intent(inout) :: Sr
 type(pawang_type),intent(in) :: Pawang
 type(wfd_t),target,intent(inout) :: Wfd,Wfdf
!arrays
 integer,intent(in) :: gwx_ngfft(18),ngfftf(18)
 type(Pawtab_type),intent(in) :: Pawtab(Psps%ntypat)
 type(pawpwff_t),intent(in) :: Paw_pwff(Psps%ntypat*Psps%usepaw)
 type(esymm_t),target,intent(in) :: allQP_sym(Wfd%nkibz,Wfd%nsppol)
 type(pawfgrtab_type),intent(inout) :: Pawfgrtab(Cryst%natom*Psps%usepaw)
 type(paw_pwaves_lmn_t),intent(in) :: Paw_onsite(Cryst%natom*Psps%usepaw)

!Local variables ------------------------------
!scalars
 integer,parameter :: tim_fourdp=2,ndat1=1
 integer,parameter :: use_pawnhat=0,ider0=0 
 integer :: izero,iab,ib_sum,ib,ib1,ib2,ierr,ig,ig_rot,ii,iik,itim_q,i2
 integer :: ik_bz,ik_ibz,isym_q,iq_bz,iq_ibz,spin,isym,jb,is_idx
 integer :: jik,jk_bz,jk_ibz,kb,mod100,nspinor,nsppol,ifft
 integer :: nq_summed,ibsp,dimcprj_gw
 integer :: spad,spadx1,spadx2,irow
 integer :: comm,ndegs,wtqm,wtqp,my_nbks
 integer :: isym_kgw,isym_ki,gwx_mgfft,use_padfft,use_padfftf,gwx_fftalga,gwx_fftalgb
 integer :: gwx_nfftot,nfftf,mgfftf
 integer :: nhat12_grdim
 real(dp) :: cpu_time,wall_time,gflops
 real(dp) :: alpha_hybrid,fact_sp,theta_mu_minus_esum,tol_empty,norm
 complex(dpc) :: ctmp,scprod,ph_mkgwt,ph_mkt
 complex(gwpc) :: gwpc_sigxme
 logical :: iscompatibleFFT,q_is_gamma
 character(len=500) :: msg
!arrays
 integer :: g0(3),spinor_padx(2,4) 
 integer,allocatable :: igfftxg0(:),igfftfxg0(:)
 integer,allocatable :: degtab(:,:,:)
 integer,allocatable :: gwx_gfft(:,:),gwx_gbound(:,:),gboundf(:,:)
 integer,allocatable ::  ktabr(:,:),irottb(:,:),ktabrf(:,:)
 integer,allocatable :: proc_distrb(:,:,:)
 real(dp) :: ksum(3),kgw(3),kgw_m_ksum(3),qbz(3),q0(3),tsec(2)
 real(dp) :: spinrot_kbz(4),spinrot_kgw(4)
 real(dp),ABI_CONTIGUOUS pointer :: qp_ene(:,:,:),qp_occ(:,:,:)
 real(dp),allocatable :: nhat12(:,:,:),grnhat12(:,:,:,:)
 complex(dpc) :: ovlp(2)
 complex(gwpc),allocatable :: vc_sqrt_qbz(:),rhotwg(:),rhotwgp(:)
 complex(gwpc),allocatable :: rhotwg_ki(:,:)
 complex(gwpc),allocatable :: wfr_bdgw(:,:),ur_ibz(:),usr_bz(:)
 complex(gwpc),allocatable :: ur_ae_sum(:),ur_ae_onsite_sum(:),ur_ps_onsite_sum(:)
 complex(gwpc),allocatable :: ur_ae_bdgw(:,:),ur_ae_onsite_bdgw(:,:),ur_ps_onsite_bdgw(:,:)
 complex(dpc),allocatable :: sigxme_tmp(:,:,:) !minbnd:maxbnd,minbnd:maxbnd,Wfd%nsppol*Sigp%nsig_ab)
 complex(dpc),allocatable :: sym_sigx(:,:),sigx(:,:,:,:)
 complex(gwpc),ABI_CONTIGUOUS pointer :: cg_jb(:),cg_sum(:)
 logical :: can_symmetrize(Wfd%nsppol)
 logical,allocatable :: bks_mask(:,:,:)
 type(esymm_t),pointer :: QP_sym(:)
 type(sigijtab_t),pointer :: Sigxij_tab(:)
 type(pawcprj_type),allocatable :: Cprj_kgw(:,:),Cprj_ksum(:,:)
 type(pawpwij_t),allocatable :: Pwij_qg(:),Pwij_fft(:)

!************************************************************************

#define DEV_USE_OLDRHOTWG 1

 DBG_ENTER("COLL")
 !
 ! === Initial check ===
 ABI_CHECK(Sigp%npwx==Gsph_x%ng,"")

 call timab(430,1,tsec) ! csigme (SigX)
 call cwtime(cpu_time,wall_time,gflops,"start")

 mod100=MOD(Sigp%gwcalctyp,100)
 !
 ! === Initialize MPI variables === 
 comm = Wfd%comm
 !
 ! === Initialize some values ===
 nspinor = Wfd%nspinor
 nsppol  = Wfd%nsppol
 spinor_padx(:,:)=RESHAPE((/0,0,Sigp%npwx,Sigp%npwx,0,Sigp%npwx,Sigp%npwx,0/),(/2,4/))
                                                                                      
 qp_ene => QP_BSt%eig(:,:,:)
 qp_occ => QP_BSt%occ(:,:,:)

 ! Exctract the symmetries of the bands for this k-point
 QP_sym => allQP_sym(sigmak_ibz,1:nsppol)

 ib1=minbnd
 ib2=maxbnd
 !
 ! === Index of the GW point in the BZ array, its image in IBZ and time-reversal ===
 jk_bz=Sigp%kptgw2bz(ikcalc)
 call get_BZ_item(Kmesh,jk_bz,kgw,jk_ibz,isym_kgw,jik,ph_mkgwt)

 ! TODO: the new version based of get_uug won't suppporte kptgw vectors that are not in
 ! the IBZ since one should perform the rotation before entering the band loop
 ! In the old version, the rotation was done in rho_tw_g
 !ABI_CHECK(jik==1,"jik!=1")
 !ABI_CHECK(isym_kgw==1,"isym_kgw!=1")
 !ABI_CHECK((ABS(ph_mkgwt - cone) < tol12),"ph_mkgwt!")

 !%call get_IBZ_item(Kmesh,jk_ibz,kibz,wtk)
 spinrot_kgw(:)=Cryst%spinrot(:,isym_kgw)
 !
 write(msg,'(2a,3f8.3,2a,2(i3,a))')ch10,&
&  ' Calculating <nk|Sigma_x|nk> at k= ',kgw,ch10,&
&  ' bands n = from ',ib1,' to ',ib2,ch10
 call wrtout(std_out,msg,'COLL')
 !
 ! === Select the mixing alpha for hybrid functional calculations if gwcalctyp >= 100
 if(Sigp%gwcalctyp<100) then 
   alpha_hybrid = 1.0_dp
 else if (Sigp%gwcalctyp>=300) then
   ! B3LYP factor = 0.20
   alpha_hybrid = 0.2_dp
 else
   ! PBE0 and HSE06 mixing determined by gwfockmix
   ! default 0.25
   alpha_hybrid = gwfockmix
 endif

 if (ANY(gwx_ngfft(1:3) /= Wfd%ngfft(1:3)) ) then
   call wfd_change_ngfft(Wfd,Cryst,Psps,gwx_ngfft) 
 end if
 gwx_mgfft   = MAXVAL(gwx_ngfft(1:3)) 
 gwx_fftalga = gwx_ngfft(7)/100
 gwx_fftalgb = MOD(gwx_ngfft(7),100)/10

 if (pawcross==1) then
   mgfftf = MAXVAL(ngfftf(1:3)) 
 end if

 can_symmetrize = .FALSE.
 if (Sigp%symsigma>0) then
   can_symmetrize = .TRUE.
   if (mod100 >= 20) then
     do spin=1,Wfd%nsppol
       can_symmetrize(spin) = .not.esymm_failed(QP_sym(spin))
       if (.not.can_symmetrize(spin)) then
         write(msg,'(a,i0,4a)')&
&          "Symmetrization cannot be performed for spin: ",spin,ch10,&
&          "band classification encountered the following problem: ",ch10,&
&          TRIM(QP_sym(spin)%err_msg)
         MSG_WARNING(msg)
       end if
     end do
   end if
   ABI_CHECK(nspinor==1,'Symmetrization with nspinor=2 not implemented')
 end if

 ABI_MALLOC(rhotwg_ki,(Sigp%npwx*nspinor,minbnd:maxbnd))
 rhotwg_ki=czero_gw
 ABI_MALLOC(rhotwg   ,(Sigp%npwx*nspinor))
 ABI_MALLOC(rhotwgp  ,(Sigp%npwx*nspinor))
 ABI_MALLOC(vc_sqrt_qbz,(Sigp%npwx))
 !
 ! === Normalization of theta_mu_minus_esum ===
 ! * If nsppol==2, qp_occ $\in [0,1]$
 SELECT CASE (nsppol)
 CASE (1)
   fact_sp=half; tol_empty=0.01   ! below this value the state is assumed empty
   if (Sigp%nspinor==2) then
    fact_sp=one; tol_empty=0.005  ! below this value the state is assumed empty
   end if
 CASE (2)
   fact_sp=one; tol_empty=0.005 ! to be consistent and obtain similar results if a metallic
 CASE DEFAULT                    ! spin unpolarized system is treated using nsppol==2
   MSG_BUG('Wrong nsppol')
 END SELECT

 ! Table for \Sigmax_ij matrix elements.
 Sigxij_tab => Sigp%Sigxij_tab(ikcalc,1:nsppol)

 ! Remove empty states from the list of states that will be distributed.
 ABI_MALLOC(bks_mask,(Wfd%mband,Kmesh%nbz,nsppol))
 bks_mask=.FALSE.
 do spin=1,nsppol
   do ik_bz=1,Kmesh%nbz
     ik_ibz = Kmesh%tab(ik_bz)
     do ib_sum=1,Sigp%nbnds
       bks_mask(ib_sum,ik_bz,spin) = (qp_occ(ib_sum,ik_ibz,spin)>=tol_empty) 
     end do
   end do
 end do

 ABI_MALLOC(proc_distrb,(Wfd%mband,Kmesh%nbz,nsppol))
 call sigma_distribute_bks(Wfd,Kmesh,Ltg_k,Qmesh,nsppol,can_symmetrize,kgw,Sigp%mg0,my_nbks,proc_distrb,bks_mask=bks_mask)

 ABI_FREE(bks_mask)

 write(msg,'(2(a,i4),a)')" Will sum ",my_nbks ," (b,k,s) occupied states in Sigma_x."
 call wrtout(std_out,msg,'PERS')
 !
 ! The index of G-G0 in the FFT mesh the oscillators ===
 ! * Sigp%mG0 gives the MAX G0 component to account for umklapp.
 ! * Note the size MAX(Sigp%npwx,Sigp%npwc).
 ABI_MALLOC(igfftxg0,(Gsph_x%ng))
 !
 ! === Precalculate the FFT index of $ R^{-1}(r-\tau) $ ===
 ! * S=\transpose R^{-1} and k_BZ = S k_IBZ
 ! * irottb is the FFT index of $R^{-1} (r-\tau)$ used to symmetrize u_Sk.
 gwx_nfftot = PRODUCT(gwx_ngfft(1:3))
 ABI_MALLOC(irottb,(gwx_nfftot,Cryst%nsym))
 call rotate_FFT_mesh(Cryst%nsym,Cryst%symrel,Cryst%tnons,gwx_ngfft,irottb,iscompatibleFFT)
 if (.not.iscompatibleFFT) then
   msg = "FFT mesh is not compatible with symmetries. Results might be affected by large errors!"
   MSG_WARNING(msg)
 end if

 ABI_MALLOC(ktabr,(gwx_nfftot,Kmesh%nbz))
 do ik_bz=1,Kmesh%nbz
   isym=Kmesh%tabo(ik_bz)
   do ifft=1,gwx_nfftot
     ktabr(ifft,ik_bz)=irottb(ifft,isym)
   end do
 end do
 ABI_FREE(irottb)

 if (Psps%usepaw==1 .and. pawcross==1) then
   nfftf = PRODUCT(ngfftf(1:3))
   ABI_MALLOC(irottb,(nfftf,Cryst%nsym))
   call rotate_FFT_mesh(Cryst%nsym,Cryst%symrel,Cryst%tnons,ngfftf,irottb,iscompatibleFFT)

   ABI_MALLOC(ktabrf,(nfftf,Kmesh%nbz))
   do ik_bz=1,Kmesh%nbz
     isym=Kmesh%tabo(ik_bz)
     do ifft=1,nfftf
       ktabrf(ifft,ik_bz)=irottb(ifft,isym)
     end do
   end do
   ABI_FREE(irottb)
 end if
 !
 ! === Additional allocations for PAW ===
 if (Psps%usepaw==1) then
   ABI_DT_MALLOC(Cprj_ksum,(Cryst%natom,nspinor))
   call pawcprj_alloc(Cprj_ksum,0,Wfd%nlmn_atm)

   nhat12_grdim=0
   if (use_pawnhat==1) then ! Compensation charge for \phi_a^*\phi_b
     call wrtout(std_out,"Using nhat12","COLL")
     ABI_MALLOC(nhat12  ,(2,gwx_nfftot,nspinor**2))
     ABI_MALLOC(grnhat12,(2,gwx_nfftot,nspinor**2,3*nhat12_grdim))
   end if
 end if ! usepaw==1
 !
 ABI_MALLOC(sigxme_tmp, (minbnd:maxbnd,minbnd:maxbnd,Wfd%nsppol*Sigp%nsig_ab))
 ABI_MALLOC(sigx,(2,ib1:ib2,ib1:ib2,nsppol*Sigp%nsig_ab))
 sigxme_tmp = czero; sigx = czero     
 
 nq_summed=Kmesh%nbz
 if (Sigp%symsigma>0) then
   call littlegroup_print(Ltg_k,std_out,prtvol,'COLL')
   nq_summed=SUM(Ltg_k%ibzq(:))
   !
   ! === Find number of complexes and number of bands in each complex ===
   ! The tolerance is a little bit arbitrary (0.001 eV)
   ! It could be reduced, in particular in case of nearly accidental degeneracies
   ABI_MALLOC(degtab,(ib1:ib2,ib1:ib2,nsppol))
   degtab=0
   do spin=1,nsppol
     do ib=ib1,ib2 
       do jb=ib1,ib2 
        if (ABS(qp_ene(ib,jk_ibz,spin)-qp_ene(jb,jk_ibz,spin))<0.001/Ha_ev) degtab(ib,jb,spin)=1
       end do
     end do
   end do
!   if (ANY(degtab/=0)) then ! If two states do not belong to the same complex => matrix elements of v_xc differ
!     write(msg,'(a,3f8.3,a)')' Degenerate states at k-point = ( ',kgw(:),' ).'
!     call wrtout(std_out,msg,'COLL')
!     do spin=1,nsppol
!       do ib=ib1,ib2 
!         do jb=ib+1,ib2 
!           if (degtab(ib,jb,spin)==1) then
!             write(msg,'(a,i2,a,i4,a,i4)')' (spin ',spin,')',ib,' <====> ',jb
!             call wrtout(std_out,msg,'COLL')
!             if (ABS(Sr%vxcme(ib,jk_ibz,spin)-Sr%vxcme(jb,jk_ibz,spin))>ABS(tol6*Sr%vxcme(jb,jk_ibz,spin))) then 
!               write(msg,'(7a)')&
!&                ' It seems that an accidental degeneracy is occurring at this k-point ',ch10,&
!&                ' In this case, using symsigma=1 might lead to spurious results as the algorithm ',ch10,&
!&                ' will treat these states as degenerate, and it won''t be able to remove the degeneracy. ',ch10,&
!&                ' In order to avoid this deficiency, run the calculation using symsigma=0'
!               MSG_WARNING(msg)
!             end if
!           end if
!         end do
!       end do
!     end do
!   end if
 end if !symsigma

 write(msg,'(2a,i6,a)')ch10,' calc_sigx_me: calculation status ( ',nq_summed,' to be completed):'
 call wrtout(std_out,msg,'COLL')

 ABI_MALLOC(ur_ibz,(gwx_nfftot*nspinor))
 ABI_MALLOC(usr_bz,(gwx_nfftot*nspinor))

 if (pawcross==1) then
   ABI_MALLOC(ur_ae_sum,(nfftf*nspinor))
   ABI_MALLOC(ur_ae_onsite_sum,(nfftf*nspinor))
   ABI_MALLOC(ur_ps_onsite_sum,(nfftf*nspinor))
 end if
 !
 ! =======================================
 ! ==== Begin loop over k_i in the BZ ====
 ! =======================================

 do spin=1,nsppol

   if (ALL(proc_distrb(:,:,spin)/=Wfd%my_rank)) CYCLE
   !
   ! * Load wavefunctions for GW corrections.
   ABI_STAT_MALLOC(wfr_bdgw,(gwx_nfftot*nspinor,ib1:ib2), ierr)
   ABI_CHECK(ierr==0, "out of memory in wfr_bdgw")
   call wfd_get_many_ur(Wfd,(/(jb, jb=ib1,ib2)/),jk_ibz,spin,wfr_bdgw)

   if (Wfd%usepaw==1) then ! * Load cprj for GW states, note the indexing.
     dimcprj_gw=nspinor*(ib2-ib1+1)
     ABI_DT_MALLOC(Cprj_kgw,(Cryst%natom,ib1:ib1+dimcprj_gw-1))
     call pawcprj_alloc(Cprj_kgw,0,Wfd%nlmn_atm)
     ibsp=ib1  
     do jb=ib1,ib2
       call wfd_get_cprj(Wfd,jb,jk_ibz,spin,Cryst,Cprj_ksum,sorted=.FALSE.)
       call paw_symcprj(jk_bz,nspinor,1,Cryst,Kmesh,Pawtab,Pawang,Cprj_ksum)
       call pawcprj_copy(Cprj_ksum,Cprj_kgw(:,ibsp:ibsp+(nspinor-1)))
       ibsp=ibsp+nspinor
     end do
     if (pawcross==1) then
       ABI_MALLOC(ur_ae_bdgw,(nfftf*nspinor,ib1:ib2))
       ABI_MALLOC(ur_ae_onsite_bdgw,(nfftf*nspinor,ib1:ib2))
       ABI_MALLOC(ur_ps_onsite_bdgw,(nfftf*nspinor,ib1:ib2))
       do jb=ib1,ib2
         call wfd_paw_get_aeur(Wfdf,jb,jk_ibz,spin,Cryst,Paw_onsite,Psps,Pawtab,Pawfgrtab,&
&          ur_ae_sum,ur_ae_onsite_sum,ur_ps_onsite_sum)
         ur_ae_bdgw(:,jb)=ur_ae_sum
         ur_ae_onsite_bdgw(:,jb)=ur_ae_onsite_sum
         ur_ps_onsite_bdgw(:,jb)=ur_ps_onsite_sum
       end do
     end if
   end if

   do ik_bz=1,Kmesh%nbz
     !
     ! === Parallelization over k-points and spin ===
     ! * For the spin there is another check in the inner loop
     if (ALL(proc_distrb(:,ik_bz,spin)/=Wfd%my_rank)) CYCLE
     !
     ! * Find the corresponding irreducible k-point
     call get_BZ_item(Kmesh,ik_bz,ksum,ik_ibz,isym_ki,iik,ph_mkt)
     spinrot_kbz(:)=Cryst%spinrot(:,isym_ki)

     ! * Identify q and G0 where q+G0=k_GW-k_i
     kgw_m_ksum=kgw-ksum
     call findqg0(iq_bz,g0,kgw_m_ksum,Qmesh%nbz,Qmesh%bz,Sigp%mG0)

     ! === Symmetrize the matrix elements ===
     ! * Sum only q"s in IBZ_k. In this case elements are weighted
     !   according to wtqp and wtqm. wtqm is for time-reversal.
     wtqp=1; wtqm=0
     if (can_symmetrize(spin)) then
       if (Ltg_k%ibzq(iq_bz)/=1) CYCLE
       wtqp=0; wtqm=0
       do isym=1,Ltg_k%nsym_sg
         wtqp=wtqp+Ltg_k%wtksym(1,isym,iq_bz)
         wtqm=wtqm+Ltg_k%wtksym(2,isym,iq_bz)
       end do
     end if

     write(msg,'(2(a,i4),a,i3)')' calc_sigx_me : ik_bz ',ik_bz,'/',Kmesh%nbz,' done by processor ',Wfd%my_rank
     call wrtout(std_out,msg,'PERS')
     !
     ! * Find the corresponding irreducible q-point.
     call get_BZ_item(Qmesh,iq_bz,qbz,iq_ibz,isym_q,itim_q)
     q_is_gamma = (normv(qbz,Cryst%gmet,"G") < GW_TOL_W0)
     !
     ! Tables for the FFT of the oscillators.
     !  a) FFT index of the G-G0.
     !  b) gwx_gbound table for the zero-padded FFT performed in rhotwg. 
     ABI_MALLOC(gwx_gbound,(2*gwx_mgfft+8,2))
     call gsph_fft_tabs(Gsph_x,g0,gwx_mgfft,gwx_ngfft,use_padfft,gwx_gbound,igfftxg0)

     if ( ANY(gwx_fftalga == (/2,4/)) ) use_padfft=0 ! Pad-FFT is not coded in rho_tw_g
     !use_padfft=0
     if (use_padfft==0) then 
       ABI_FREE(gwx_gbound)
       ABI_MALLOC(gwx_gbound,(2*gwx_mgfft+8,2*use_padfft))
     end if

     if (pawcross==1) then
       ABI_MALLOC(gboundf,(2*mgfftf+8,2))
       ABI_MALLOC(igfftfxg0,(Gsph_x%ng))
       call gsph_fft_tabs(Gsph_x,g0,mgfftf,ngfftf,use_padfftf,gboundf,igfftfxg0)
       if ( ANY(gwx_fftalga == (/2,4/)) ) use_padfftf=0
       if (use_padfftf==0) then 
         ABI_FREE(gboundf)
         ABI_MALLOC(gboundf,(2*mgfftf+8,2*use_padfftf))
       end if
     end if
     !
     ! === Evaluate oscillator matrix elements ===
     ! * $ <phj/r|e^{-i(q+G)}|phi/r> - <tphj/r|e^{-i(q+G)}|tphi/r> $ in packed form.
     if (Psps%usepaw==1.and.use_pawnhat==0) then
       q0 = qbz !;if (q_is_gamma) q0 = (/0.00001_dp,0.00001_dp,0.00001_dp/) ! GW_Q0_DEFAULT
       ABI_DT_MALLOC(Pwij_qg,(Psps%ntypat))
       call pawpwij_init(Pwij_qg,Sigp%npwx,q0,Gsph_x%gvec,Cryst%rprimd,Psps,Pawtab,Paw_pwff)
     end if
     !
     ! === Get Fourier components of the Coulomb interaction in the BZ ===
     ! * In 3D systems, neglecting umklapp,  vc(Sq,sG)=vc(q,G)=4pi/|q+G|
     ! * The same relation holds for 0-D systems, but not in 1-D or 2D systems. It depends on S.
     do ig=1,Sigp%npwx
       ig_rot = Gsph_x%rottb(ig,itim_q,isym_q)
       vc_sqrt_qbz(ig_rot)=Vcp%vc_sqrt(ig,iq_ibz)
     end do
     !
     ! === Sum over bands ===
     do ib_sum=1,Sigp%nbnds
       !
       ! === Parallelism over spin ===
       ! * This processor has this k-point but what about spin?
       if (proc_distrb(ib_sum,ik_bz,spin)/=Wfd%my_rank) CYCLE
       !
       ! * Skip empty states.
       if (qp_occ(ib_sum,ik_ibz,spin)<tol_empty) CYCLE

#if DEV_USE_OLDRHOTWG
       call wfd_get_ur(Wfd,ib_sum,ik_ibz,spin,ur_ibz)
#else
       call wfd_sym_ur(Wfd,Cryst,Kmesh,ib_sum,ik_bz,spin,usr_bz,trans="C",with_umklp=.FALSE.,ur_kibz=ur_ibz)
#endif

       if (Psps%usepaw==1) then ! Load cprj for point ksum, this spin or spinor and *THIS* band.
         ! TODO MG I could avoid doing this but I have to exchange spin and bands ???
         ! For sure there is a better way to do this!
         call wfd_get_cprj(Wfd,ib_sum,ik_ibz,spin,Cryst,Cprj_ksum,sorted=.FALSE.)
         call paw_symcprj(ik_bz,nspinor,1,Cryst,Kmesh,Pawtab,Pawang,Cprj_ksum)
         if (pawcross==1) then
           call wfd_paw_get_aeur(Wfdf,ib_sum,ik_ibz,spin,Cryst,Paw_onsite,Psps,Pawtab,Pawfgrtab,&
&              ur_ae_sum,ur_ae_onsite_sum,ur_ps_onsite_sum)
         end if
       end if

       do jb=ib1,ib2 ! Get all <k-q,ib_sum,s|e^{-i(q+G).r}|s,jb,k>

         if (Psps%usepaw==1.and.use_pawnhat==1) then 
           MSG_ERROR("use_pawnhat is disabled")
           i2=jb; if (nspinor==2) i2=(2*jb-1)
           spad=(nspinor-1)

           izero=0
           call pawmknhat_psipsi(Cprj_ksum,Cprj_kgw(:,i2:i2+spad),ider0,izero,Cryst%natom,&
&            Cryst%natom,gwx_nfftot,gwx_ngfft,nhat12_grdim,nspinor,Cryst%ntypat,Pawang,Pawfgrtab,&
&            grnhat12,nhat12,pawtab)

         else

#if DEV_USE_OLDRHOTWG
           call rho_tw_g(nspinor,Sigp%npwx,gwx_nfftot,ndat1,gwx_ngfft,1,use_padfft,igfftxg0,gwx_gbound,&
&            ur_ibz        ,iik,ktabr(:,ik_bz),ph_mkt  ,spinrot_kbz,&
&            wfr_bdgw(:,jb),jik,ktabr(:,jk_bz),ph_mkgwt,spinrot_kgw,&
&            nspinor,rhotwg_ki(:,jb))
#else
           call get_uug(Sigp%npwx,gwx_nfftot,ndat1,gwx_ngfft,use_padfft,igfftxg0,gwx_gbound,usr_bz,wfr_bdgw(:,jb),rhotwg_ki(:,jb))
#endif

           if (Psps%usepaw==1.and.use_pawnhat==0) then ! Add on-site contribution, projectors are already in BZ.
             i2=jb; if (nspinor==2) i2=(2*jb-1)
             spad=(nspinor-1)
             call paw_rho_tw_g(Sigp%npwx,nspinor,nspinor,Cryst%natom,Cryst%ntypat,Cryst%typat,Cryst%xred,Gsph_x%gvec,&
&              Cprj_ksum(:,:),Cprj_kgw(:,i2:i2+spad),Pwij_qg,rhotwg_ki(:,jb))
           end if
           if (Psps%usepaw==1.and.pawcross==1) then ! Add paw cross term
             call paw_cross_rho_tw_g(nspinor,Sigp%npwx,nfftf,ngfftf,1,use_padfftf,igfftfxg0,gboundf,&
&             ur_ae_sum,ur_ae_onsite_sum,ur_ps_onsite_sum,iik,ktabrf(:,ik_bz),ph_mkt,spinrot_kbz,&
&             ur_ae_bdgw(:,jb),ur_ae_onsite_bdgw(:,jb),ur_ps_onsite_bdgw(:,jb),jik,ktabrf(:,jk_bz),ph_mkgwt,spinrot_kgw,&
&             nspinor,rhotwg_ki(:,jb))
           end if
         end if
         !
         ! === Multiply by the square root of the Coulomb term ===
         ! * In 3-D systems, the factor sqrt(4pi) is included)
         do ii=1,nspinor
           spad=(ii-1)*Sigp%npwx
!!$omp parallel workshare
           rhotwg_ki(spad+1:spad+Sigp%npwx,jb)=rhotwg_ki(spad+1:spad+Sigp%npwx,jb)*vc_sqrt_qbz(1:Sigp%npwx)
!!$omp end parallel workshare
         end do
         !
         ! === Treat analytically the case q --> 0 ===
         ! * The oscillator is evaluated at q=O as it is considered constant in the small cube around Gamma
         !   while the Colulomb term is integrated out.
         ! * In the scalar case we have nonzero contribution only if ib_sum==jb
         ! * For nspinor==2 evalute <ib_sum,up|jb,up> and <ib_sum,dwn|jb,dwn>,
         !   impose orthonormalization since npwwfn might be < npwvec.
         if (ik_bz==jk_bz) then
           if (nspinor==1) then
             rhotwg_ki(1,jb)=czero_gw
             if (ib_sum==jb) rhotwg_ki(1,jb)=CMPLX(SQRT(Vcp%i_sz),0.0_gwp)
           else
             ! TODO Recheck this!
             cg_sum  => Wfd%Wave(ib,ik_ibz,spin)%ug
             cg_jb   => Wfd%Wave(jb,jk_ibz,spin)%ug

             ctmp = xdotc(Wfd%npwwfn*Wfd%nspinor,cg_sum,1,cg_jb,1) 
             ovlp(1) = REAL(ctmp) 
             ovlp(2) = AIMAG(ctmp) 

             if (Psps%usepaw==1) then
               i2=(2*jb-1)
               ovlp = ovlp + paw_overlap(Cprj_ksum,Cprj_kgw(:,i2:i2+1),Cryst%typat,Pawtab)
             end if
             !ovlp(2) = -ovlp(1)
             !if (ib_sum==jb) ovlp(2)=cone_gw-ovlp(1)
             if (ib_sum==jb) then
               norm=DBLE(ovlp(1)+ovlp(2))
               ovlp(1)=DBLE(ovlp(1)/norm)
               ovlp(2)=DBLE(ovlp(2)/norm)
             else
               scprod=ovlp(1)+ovlp(2)
               ovlp(1)=ovlp(1)-scprod*half
               ovlp(2)=ovlp(2)-scprod*half
             end if
             rhotwg_ki(1          ,jb)=CMPLX(SQRT(Vcp%i_sz),0.0_gwp)*ovlp(1)
             rhotwg_ki(Sigp%npwx+1,jb)=CMPLX(SQRT(Vcp%i_sz),0.0_gwp)*ovlp(2)
           end if
         end if
       end do !jb Got all matrix elements from minbnd up to maxbnd.

       theta_mu_minus_esum=fact_sp*qp_occ(ib_sum,ik_ibz,spin)

       do kb=ib1,ib2
         !
         ! * The ket Sigma|phi_{k,kb}>.
         rhotwgp(:)=rhotwg_ki(:,kb)
         !
         ! Loop over the non-zero row elements of this column.
         ! 1) If mod100<20 : only diagonal elements since QP==KS.
         ! 2) If mod100>=20:
         !     * Only off-diagonal elements connecting states with same character.
         !     * Only the upper triangle if HF, SEX, or COHSEX. 
         do irow=1,Sigxij_tab(spin)%col(kb)%size1

           jb = Sigxij_tab(spin)%col(kb)%bidx(irow)
           rhotwg=rhotwg_ki(:,jb)

           ! === Calculate bare exchange <phi_j|Sigma_x|phi_k> ===
           ! * Do the scalar product only if ib_sum is occupied.
           if (theta_mu_minus_esum/fact_sp >= tol_empty) then
             do iab=1,Sigp%nsig_ab
               spadx1=spinor_padx(1,iab)
               spadx2=spinor_padx(2,iab)

               gwpc_sigxme=-XDOTC(Sigp%npwx,rhotwg(spadx1+1:),1,rhotwgp(spadx2+1:),1)*theta_mu_minus_esum
               !
               ! === Accumulate and symmetrize Sigma_x ===
               ! * -wtqm comes from time-reversal (exchange of band indeces)
               is_idx=spin; if (nspinor==2) is_idx=iab

               sigxme_tmp(jb,kb,is_idx) = sigxme_tmp(jb,kb,is_idx) + & 
&                (wtqp+wtqm)*DBLE(gwpc_sigxme) + (wtqp-wtqm)*j_gw*AIMAG(gwpc_sigxme)

               sigx(1,jb,kb,is_idx) = sigx(1,jb,kb,is_idx) + wtqp *      gwpc_sigxme
               sigx(2,jb,kb,is_idx) = sigx(2,jb,kb,is_idx) + wtqm *CONJG(gwpc_sigxme)
             end do
           end if
           !
         end do ! jb used to calculate matrix elements of Sigma_x

       end do !kb to calculate matrix elements of Sigma_x
     end do !ib_sum
     !
     ! Deallocate k-dependent quantities.
     ABI_FREE(gwx_gbound)
     if (pawcross==1) then
       ABI_FREE(gboundf)
     end if

     if (Psps%usepaw==1.and.use_pawnhat==0) then
       call pawpwij_free(Pwij_qg)
       ABI_DT_FREE(Pwij_qg)
     end if
   end do !ik_bz Got all diagonal (off-diagonal) matrix elements.

   ABI_FREE(wfr_bdgw)
   if (Wfd%usepaw==1) then
     call pawcprj_free(Cprj_kgw )
     ABI_DT_FREE(Cprj_kgw)
     if (pawcross==1) then
       ABI_FREE(ur_ae_bdgw)
       ABI_FREE(ur_ae_onsite_bdgw)
       ABI_FREE(ur_ps_onsite_bdgw)
     end if
   end if
 end do !spin

 ABI_FREE(igfftxg0)
 if (pawcross==1) then
   ABI_FREE(igfftfxg0)
 end if
 !
 ! Gather contributions from all the CPUs.
 call xmpi_sum(sigxme_tmp,comm,ierr)
 call xmpi_sum(sigx,comm,ierr)
 !
 ! === Multiply by constants ===
 ! * For 3D systems sqrt(4pi) is included in vc_sqrt_qbz ===
 sigxme_tmp = (one/(Cryst%ucvol*Kmesh%nbz)) * sigxme_tmp * alpha_hybrid
 sigx       = (one/(Cryst%ucvol*Kmesh%nbz)) * sigx       * alpha_hybrid
 !
 ! === If we have summed over the IBZ_q now we have to average over complexes ===
 ! * Presently only diagonal terms are considered
 ! * TODO QP-SCGW required a more involved approach, there is a check in sigma
 ! * TODO it does not work if spinor==2.

 do spin=1,nsppol
   if (can_symmetrize(spin)) then
     ABI_MALLOC(sym_sigx,(ib1:ib2,ib1:ib2))
     sym_sigx=czero
     !
     ! === Average over degenerate diagonal elements ===
     ! NOTE: frequencies for \Sigma_c(\omega) should be equal to avoid spurious results.
     ! another good reason to use a strict criterion for the tollerance on eigenvalues.
     do ib=ib1,ib2 
       ndegs=0
       do jb=ib1,ib2 
         if (degtab(ib,jb,spin)==1) then
           sym_sigx(ib,ib)=sym_sigx(ib,ib) +SUM(sigx(:,jb,jb,spin))
         end if
         ndegs=ndegs+degtab(ib,jb,spin)
       end do
       sym_sigx(ib,ib)=sym_sigx(ib,ib)/ndegs
     end do

     if (mod100 >= 20) then 
       call esymm_symmetrize_mels(QP_sym(spin),ib1,ib2,sigx(:,:,:,spin),sym_sigx)
     end if
     !
     ! ==== Copy symmetrized values ====
     do ib=ib1,ib2
       do jb=ib1,ib2 
         sigxme_tmp(ib,jb,spin)=sym_sigx(ib,jb)
       end do
     end do

     ABI_FREE(sym_sigx)
   end if
 end do

 if (mod100>=20) then 
   ! Reconstruct the full sigma_x matrix from the upper triangle.
   ABI_CHECK(nspinor==1,"cannot hermitianize non-collinear sigma!")
   do spin=1,nsppol
     call hermitianize(sigxme_tmp(:,:,spin),"Upper")
   end do
 end if

 ! === Save diagonal elements or ab components of Sigma_x (hermitian) ===
 ! TODO It should be hermitian also if nspinor==2
 do spin=1,nsppol
   do jb=ib1,ib2
     do iab=1,Sigp%nsig_ab
       is_idx=spin; if (Sigp%nsig_ab>1) is_idx=iab
       Sr%sigxme(jb,jk_ibz,is_idx) = DBLE(sigxme_tmp(jb,jb,is_idx))
     end do
     !if (Sigp%nsig_ab>1) then 
     !  write(std_out,'(i3,4f8.3,a,f8.3)')jb,Sr%sigxme(jb,jk_ibz,:)*Ha_eV,' Tot ',SUM(Sr%sigxme(jb,jk_ibz,:))*Ha_eV
     !end if
   end do 
 end do 

 ! Save full exchange matrix in Sr%
 Sr%x_mat(minbnd:maxbnd,minbnd:maxbnd,jk_ibz,:) = sigxme_tmp(minbnd:maxbnd,minbnd:maxbnd,:)
 ABI_FREE(sigxme_tmp)
 !
 ! ===========================
 ! ==== Deallocate memory ====
 ! ===========================
 if (Psps%usepaw==1) then
   if (allocated(gwx_gfft))  then
     ABI_FREE(gwx_gfft)
   end if
   call pawcprj_free(Cprj_ksum)
   ABI_DT_FREE(Cprj_ksum)
   if (allocated(Pwij_fft)) then
     call pawpwij_free(Pwij_fft)
     ABI_DT_FREE(Pwij_fft)
   end if
   if (use_pawnhat==1) then
     ABI_FREE(nhat12)
     ABI_FREE(grnhat12)
   end if
   if (pawcross==1) then
     ABI_FREE(ur_ae_sum)
     ABI_FREE(ur_ae_onsite_sum)
     ABI_FREE(ur_ps_onsite_sum)
     ABI_FREE(ktabrf)
   end if
 end if

 ABI_FREE(ur_ibz)
 ABI_FREE(usr_bz)
 ABI_FREE(rhotwg_ki)
 ABI_FREE(rhotwg)
 ABI_FREE(rhotwgp)
 ABI_FREE(vc_sqrt_qbz)
 ABI_FREE(ktabr)
 ABI_FREE(sigx)
 ABI_FREE(proc_distrb)

 if (allocated(degtab)) then
   ABI_FREE(degtab)
 end if

 call timab(430,2,tsec) ! csigme (SigX)
 call cwtime(cpu_time,wall_time,gflops,"stop")
 write(std_out,'(2(a,f9.1))')" cpu_time = ",cpu_time,", wall_time = ",wall_time

 DBG_EXIT("COLL")

end subroutine calc_sigx_me
!!***
