/*==============================================================================
================================================================================
	 ▌ ETUDE SUR LA SANTE DES TRAVAILLEUSES
	 ▌ DOMESTIQUES EN AFRIQUE DE L'OUEST : CAS DU BURKINA FASO
	 ▌ Institut National de la Statistique et de la Démographie (INSD)
================================================================================
================================================================================
Ce programme procède en 2 temps :
		(1) apurement de la base MENAGE ;
		(2) "reconstitution" et apurement de la base INDIVIDU ;
	avec, à chaque étape, un classeur Excel de "listing d'erreurs"
	(onglet "description des erreurs" + un onglet listN par anomalie)

	Ici, les 2 niveaux de collecte sont :
		NIVEAU 1 - "FICHE DE DENOMBREMENT DES MENAGES" : passage dans chaque 
		           concession pour repérer les ménages ayant au moins une
		           travailleuse domestique (TD) -> Blocs A1 à A12 ;
		NIVEAU 2 - "QUESTIONNAIRE VOLET QUANTITATIF" : administré directement à 
		           chaque TD repérée -> 96 questions, 9 parties.

	Résultats attendus :
	- labelliser correctement les 2 bases (variables + modalités) ;
	- détecter les erreurs probables de collecte à chaque niveau ;
	- exporter les erreurs vers Excel pour décision (validation/correction) ;
	- rapprocher les 2 bases (nombre de TD annoncées au dénombrement vs nombre
	  de TD effectivement interviewées) pour mesurer la couverture ;
	- constituer les bases apurées finales.
================================================================================
===============================================================================*/

clear all
set more off
version 17

/*=========================================================================================
	SECTION 0 : PARAMETRAGE DES REPERTOIRES DE TRAVAIL
===========================================================================================*/

	global repertoire "C:\Users\User\Desktop\Enquete_TravailleusesDomestiques_BFA"

	capture mkdir "$repertoire"
	capture mkdir "$repertoire/Bases brutes reconstituees"
	global brute "$repertoire/Bases brutes reconstituees"

	capture mkdir "$repertoire/Fichiers temporaires"
	global temp "$repertoire/Fichiers temporaires"

	capture mkdir "$repertoire/Fichiers des erreurs probables"
	global listing "$repertoire/Fichiers des erreurs probables"

	capture mkdir "$repertoire/bases apurees"
	global sortie "$repertoire/bases apurees"


/*=========================================================================================
	SECTION 0bis : PARAMETRES DES CONTROLES ET PROGRAMMES UTILITAIRES (NOUVEAU)
	-> à ne pas modifier, sauf les interrupteurs ci-dessous (1 = oui, 0 = non)
===========================================================================================*/

	global lister_dates_imputees  0		// 1 = onglet listant TOUTES les dates de naissance imputées (jour_nais=1 ou 15, mois=7)
	global lister_smq03d_vide     0		// 1 = onglet "année de naissance connue ET smq03d vide" (normal d'après le questionnaire)
	global option_vide_est_erreur 1		// 1 = une option vide (. ou .a) dans une question à cases à cocher Oui/Non POSEE est une anomalie
	global seuil_superieur_age    17	// alerte : niveau "Supérieur" (smq05=5) déclaré avant cet âge
	global seuil_secondaire_age   12	// alerte : niveau "Secondaire" (smq05=4) déclaré avant cet âge
	global ctl_absentes ""

	capture mkdir "$repertoire/Graphiques"
	global graphiques "$repertoire/Graphiques"	// dossier où sont enregistrés les graphiques (PNG)

	*Prépare les compteurs génériques (à appeler une fois par base)
	capture program drop ctl_init
	program define ctl_init
		version 17
		gen int erreur_manq_oblig   = 0
		gen int erreur_hors_filtre  = 0
		gen int erreur_modalite     = 0
		gen int erreur_multi_aucun  = 0
		gen str2000 liste_manq_oblig  = ""
		gen str2000 liste_hors_filtre = ""
		gen str2000 liste_modalite    = ""
		gen str2000 liste_multi_aucun = ""
		label variable erreur_manq_oblig  "Anomalie : nb de questions POSEES mais non renseignées (détail variable par variable dans l'onglet 'corrections terrain')"
		label variable erreur_hors_filtre "Anomalie : nb de questions renseignées alors qu'elles NE DEVAIENT PAS être posées (détail dans l'onglet 'corrections terrain')"
		label variable erreur_modalite    "Anomalie : nb de modalités/valeurs incorrectes (détail dans l'onglet 'corrections terrain')"
		label variable erreur_multi_aucun "Anomalie : question à cases à cocher posée mais aucune option cochée Oui (détail dans l'onglet 'corrections terrain')"
		label variable liste_manq_oblig   "Variables posées mais non renseignées"
		label variable liste_hors_filtre  "Variables renseignées alors que le filtre ne le permet pas"
		label variable liste_modalite     "Variables à modalité/valeur incorrecte"
		label variable liste_multi_aucun  "Questions à cases à cocher sans aucun Oui"
		global ctl_np 0
		global ctl_nom_manq ""
		global ctl_n_manq ""
		global ctl_nom_hf ""
		global ctl_n_hf ""
	end

	*  alimente l'onglet "corrections terrain" (voir ctl_export)
	capture program drop ctl_poste
	program define ctl_poste
		version 17
		args v pb typ raison nomaff valeurtxt libtxt
		quietly count if `pb'==1
		if r(N) == 0 exit
		local kv ""
		foreach w in $ctl_keyvars {
			capture confirm variable `w'
			if _rc==0 local kv `kv' `w'
		}
		global ctl_np = ${ctl_np} + 1
		preserve
			quietly keep if `pb'==1
			capture confirm string variable `v'
			if _rc==0 {
				quietly gen str244 ctl_valeur = cond(trim(`v')=="", "(vide)", substr(trim(`v'),1,240))
			}
			else {
				quietly gen str40 ctl_valeur = string(`v')
			}
			if `"`valeurtxt'"' != "" quietly replace ctl_valeur = `"`valeurtxt'"'
			local lb : variable label `v'
			if `"`libtxt'"' != "" local lb `"`libtxt'"'
			local nom "`v'"
			if "`nomaff'" != "" local nom "`nomaff'"
			keep `kv' ctl_valeur
			quietly gen str40 variable = "`nom'"
			quietly gen str244 libelle = `"`lb'"'
			quietly gen str30 type_anomalie = "`typ'"
			quietly gen str500 regle = `"`raison'"'
			quietly save "$temp/ctl_part${ctl_np}.dta", replace
		restore
	end

	* ---- Contrôle d'UNE question : manquant si posée / renseignée si non posée / modalité valide ----
	capture program drop ctl_q
	program define ctl_q
		version 17
		syntax anything(name=v), Si(string) [Codes(string) Plage(string)]
		local v = trim("`v'")
		capture confirm variable `v'
		if _rc != 0 {
			global ctl_absentes "${ctl_absentes} `v'"
			exit
		}
		tempvar actif vide ok
		capture gen byte `actif' = (`si')
		if _rc != 0 {
			global ctl_absentes "${ctl_absentes} (condition de `v')"
			exit
		}
		quietly replace `actif' = 0 if missing(`actif')
		capture confirm string variable `v'
		local estchaine = (_rc==0)
		if `estchaine' == 1 {
			quietly gen byte `vide' = (trim(`v')=="" | trim(`v')=="." | trim(`v')=="##N/A##")
		}
		else {
			quietly gen byte `vide' = missing(`v')
		}
		quietly replace erreur_manq_oblig = erreur_manq_oblig + 1 if `actif'==1 & `vide'==1
		quietly replace liste_manq_oblig = liste_manq_oblig + cond(liste_manq_oblig=="", "", " ") + "`v'" if `actif'==1 & `vide'==1
		quietly replace erreur_hors_filtre = erreur_hors_filtre + 1 if `actif'!=1 & `vide'==0
		quietly replace liste_hors_filtre = liste_hors_filtre + cond(liste_hors_filtre=="", "", " ") + "`v'" if `actif'!=1 & `vide'==0
		* condition en langage lisible pour l'onglet "corrections terrain"
		local sitxt = subinstr("`si'", "ctl_td==1", "TD identifiée et consentante", .)
		local sitxt = subinstr("`sitxt'", "!missing(", "renseigné(", .)
		local sitxt = subinstr("`sitxt'", " & ", " ET ", .)
		local sitxt = subinstr("`sitxt'", " | ", " OU ", .)
		local sitxt = subinstr("`sitxt'", "!=", " différent de ", .)
		local sitxt = subinstr("`sitxt'", "==", " = ", .)
		if trim("`si'") == "1==1" local sitxt "question posée à tous"
		tempvar pbm pbh
		quietly gen byte `pbm' = (`actif'==1 & `vide'==1)
		ctl_poste `v' `pbm' "Manquant" "Question posée (condition : `sitxt') mais non renseignée"
		quietly gen byte `pbh' = (`actif'!=1 & `vide'==0)
		ctl_poste `v' `pbh' "Hors filtre" "Renseignée alors qu'elle n'aurait pas dû être posée (condition non remplie : `sitxt')"
		quietly count if `actif'==1 & `vide'==1
		global ctl_nom_manq "${ctl_nom_manq} `v'"
		global ctl_n_manq "${ctl_n_manq} `r(N)'"
		quietly count if `actif'!=1 & `vide'==0
		global ctl_nom_hf "${ctl_nom_hf} `v'"
		global ctl_n_hf "${ctl_n_hf} `r(N)'"
		if "`codes'" != "" & `estchaine' == 0 {
			numlist "`codes'"
			local lc `r(numlist)'
			quietly gen byte `ok' = 0
			foreach c of local lc {
				quietly replace `ok' = 1 if `v' == `c'
			}
			tempvar pbo
			quietly gen byte `pbo' = (`vide'==0 & `ok'==0)
			ctl_poste `v' `pbo' "Modalité invalide" "Valeur hors des modalités du questionnaire (valeurs acceptées : `codes')"
			quietly replace erreur_modalite = erreur_modalite + 1 if `vide'==0 & `ok'==0
			quietly replace liste_modalite = liste_modalite + cond(liste_modalite=="", "", " ") + "`v'" if `vide'==0 & `ok'==0
		}
		if "`plage'" != "" & `estchaine' == 0 {
			tokenize `plage'
			local lo `1'
			local hi `2'
			tempvar pbp
			quietly gen byte `pbp' = (`vide'==0 & (`v' < `lo' | `v' > `hi'))
			ctl_poste `v' `pbp' "Valeur hors plage" "Valeur attendue entre `lo' et `hi'"
			quietly replace erreur_modalite = erreur_modalite + 1 if `vide'==0 & (`v' < `lo' | `v' > `hi')
			quietly replace liste_modalite = liste_modalite + cond(liste_modalite=="", "", " ") + "`v'" if `vide'==0 & (`v' < `lo' | `v' > `hi')
		}
	end

	* ---- Contrôle d'une question à CASES A COCHER (Oui/Non) : variables stem__1 ... stem__nb ----
	capture program drop ctl_multi
	program define ctl_multi
		version 17
		syntax anything(name=stem), Nb(integer) Si(string) [Aumoinsun]
		local stem = trim("`stem'")
		tempvar actif nvide nyes
		capture gen byte `actif' = (`si')
		if _rc != 0 {
			global ctl_absentes "${ctl_absentes} (condition de `stem')"
			exit
		}
		quietly replace `actif' = 0 if missing(`actif')
		local sitxt = subinstr("`si'", "ctl_td==1", "TD identifiée et consentante", .)
		local sitxt = subinstr("`sitxt'", " & ", " ET ", .)
		local sitxt = subinstr("`sitxt'", " | ", " OU ", .)
		local sitxt = subinstr("`sitxt'", "==", " = ", .)
		quietly gen int `nvide' = 0
		quietly gen int `nyes'  = 0
		forvalues k = 1/`nb' {
			capture confirm variable `stem'__`k'
			if _rc != 0 {
				global ctl_absentes "${ctl_absentes} `stem'__`k'"
			}
			else {
				if ${option_vide_est_erreur} == 1 {
					quietly replace erreur_manq_oblig = erreur_manq_oblig + 1 if `actif'==1 & missing(`stem'__`k')
					quietly replace liste_manq_oblig = liste_manq_oblig + cond(liste_manq_oblig=="", "", " ") + "`stem'__`k'" if `actif'==1 & missing(`stem'__`k')
				}
				quietly replace erreur_hors_filtre = erreur_hors_filtre + 1 if `actif'!=1 & !missing(`stem'__`k')
				quietly replace liste_hors_filtre = liste_hors_filtre + cond(liste_hors_filtre=="", "", " ") + "`stem'__`k'" if `actif'!=1 & !missing(`stem'__`k')
				quietly replace erreur_modalite = erreur_modalite + 1 if !missing(`stem'__`k') & !inlist(`stem'__`k', 0, 1)
				quietly replace liste_modalite = liste_modalite + cond(liste_modalite=="", "", " ") + "`stem'__`k'" if !missing(`stem'__`k') & !inlist(`stem'__`k', 0, 1)
				quietly replace `nvide' = `nvide' + 1 if missing(`stem'__`k')
				quietly replace `nyes'  = `nyes'  + 1 if `stem'__`k' == 1
				tempvar pbm pbh pbo
				quietly gen byte `pbm' = (`actif'==1 & missing(`stem'__`k'))
				if ${option_vide_est_erreur} == 1 ctl_poste `stem'__`k' `pbm' "Manquant (case à cocher)" "Option de la question à cases à cocher non renseignée (ni Oui ni Non) alors que la question est posée (condition : `sitxt')"
				quietly gen byte `pbh' = (`actif'!=1 & !missing(`stem'__`k'))
				ctl_poste `stem'__`k' `pbh' "Hors filtre" "Case renseignée alors que la question n'aurait pas dû être posée (condition non remplie : `sitxt')"
				quietly gen byte `pbo' = (!missing(`stem'__`k') & !inlist(`stem'__`k', 0, 1))
				ctl_poste `stem'__`k' `pbo' "Modalité invalide" "Valeur autre que 0 (Non) ou 1 (Oui)"
				quietly count if `actif'==1 & missing(`stem'__`k')
				local cm = r(N)
				quietly count if `actif'!=1 & !missing(`stem'__`k')
				local ch = r(N)
				if ${option_vide_est_erreur} == 1 {
					global ctl_nom_manq "${ctl_nom_manq} `stem'__`k'"
					global ctl_n_manq "${ctl_n_manq} `cm'"
				}
				global ctl_nom_hf "${ctl_nom_hf} `stem'__`k'"
				global ctl_n_hf "${ctl_n_hf} `ch'"
			}
		}
		if "`aumoinsun'" != "" {
			tempvar pba
			if ${option_vide_est_erreur} == 1 {
				quietly gen byte `pba' = (`actif'==1 & `nvide'==0 & `nyes'==0)
			}
			else {
				quietly gen byte `pba' = (`actif'==1 & `nyes'==0)
			}
			capture confirm variable `stem'__1
			if _rc==0 ctl_poste `stem'__1 `pba' "Aucune option cochée Oui" "Question à cases à cocher posée (condition : `sitxt') : au moins une option doit être Oui" "`stem'" "(toutes les options = Non)" "Question à cases à cocher `stem' : aucune option cochée Oui"
			if ${option_vide_est_erreur} == 1 {
				quietly replace erreur_multi_aucun = erreur_multi_aucun + 1 if `actif'==1 & `nvide'==0 & `nyes'==0
				quietly replace liste_multi_aucun = liste_multi_aucun + cond(liste_multi_aucun=="", "", " ") + "`stem'" if `actif'==1 & `nvide'==0 & `nyes'==0
			}
			else {
				quietly replace erreur_multi_aucun = erreur_multi_aucun + 1 if `actif'==1 & `nyes'==0
				quietly replace liste_multi_aucun = liste_multi_aucun + cond(liste_multi_aucun=="", "", " ") + "`stem'" if `actif'==1 & `nyes'==0
			}
		}
	end

	* ---- Enregistre un indicateur dans la liste des listings à exporter ----
	capture program drop addflag
	program define addflag
		version 17
		args f vars desc
		global nflags = ${nflags} + 1
		global flag${nflags}  "`f'"
		global fvars${nflags} "`vars'"
		global fdesc${nflags} "`desc'"
	end


	* ---- Graphiques de synthèse (PNG enregistrés dans $graphiques) ----
	capture program drop ctl_graphs
	program define ctl_graphs
		version 17
		syntax, Prefixe(string) Statut(varname) Anom(varname) [Si(string) Enq(varname) Titre(string)]
		capture mkdir "$graphiques"
		preserve
			if "`si'" != "" quietly keep if `si'
			quietly count
			if r(N) == 0 {
				restore
				exit
			}
			local ntot = r(N)

			* ---- chiffres nécessaires (calculés avant de remplacer la base en mémoire) ----
			tempvar st
			quietly gen str60 `st' = ustrregexra(`statut', "^[^ ]+ ", "")
			quietly count if `st'=="Normal"
			local c1 = r(N)
			quietly count if `st'=="Alerte(s) à vérifier"
			local c2 = r(N)
			quietly count if `st'=="A surveiller"
			local c3 = r(N)
			quietly count if `st'=="A corriger"
			local c4 = r(N)

			local nbf = 0
			forvalues k = 1/$nflags {
				local f ${flag`k'}
				if substr("`f'",1,6) == "erreur" {
					quietly count if `f' > 0 & !missing(`f')
					local ++nbf
					local fn`nbf' = subinstr("`f'", "erreur_", "", 1)
					local fc`nbf' = r(N)
				}
			}

			* ---- Graphique 1 : répartition des statuts de contrôle ----
			capture noisily {
				clear
				set obs 4
				gen byte ordre = _n
				gen double pct = .
				forvalues i = 1/4 {
					replace pct = 100 * `c`i'' / `ntot' in `i'
				}
				label define lbl_statut 1 "Normal" 2 "Alerte(s)" 3 "A surveiller" 4 "A corriger"
				label values ordre lbl_statut
				graph bar (asis) pct, over(ordre) asyvars legend(off) blabel(bar, format(%4.1f)) ///
					bar(1, color(green)) bar(2, color(yellow)) bar(3, color(orange)) bar(4, color(red)) ///
					title("Statut de contrôle qualité (% des lignes)") subtitle("`titre' -- effectif : `ntot'") ///
					ytitle("%") graphregion(color(white))
				graph export "$graphiques/`prefixe'_1_statuts_controle.png", replace width(1600)
			}

		restore
	end

	* ---- Exporte tous les indicateurs enregistrés (1 onglet par indicateur ayant des cas) ----
	capture program drop ctl_export
	program define ctl_export
		version 17
		syntax using/, IDvars(string) [DICO]
		forvalues k = 1/$nflags {
			local f ${flag`k'}
			quietly count if `f' > 0 & !missing(`f')
			local n`k' = r(N)
		}
		putexcel clear
		putexcel set "`using'", sheet("description des erreurs") replace
		putexcel a1="nom de la feuille" b1="description du listing contenu dans la feuille" c1="nombre de cas trouvés" d1="onglet créé ?" e1="type" f1="variables concernées (nom = label)"
		putexcel a1:f1, bold
		putexcel h1 = "Version du programme : test3 v2 (descriptions complètes, sans coupure à 80 caractères)"
		forvalues k = 1/$nflags {
			local f ${flag`k'}
			local row = `k' + 1
			local lb `"${fdesc`k'}"'
			if `"`lb'"' == "" local lb : variable label `f'
			local typ "Erreur (comptée dans nb_anomalies)"
			if substr("`f'",1,6)=="alerte" local typ "Alerte à vérifier (non comptée)"
			if substr("`f'",1,6)=="detail" local typ "Détail (déjà compté dans une autre ligne)"
			if substr("`f'",1,4)=="info" local typ "Information (non comptée)"
			local vd ""
			foreach w in ${fvars`k'} {
				capture confirm variable `w'
				if _rc==0 {
					local wl : variable label `w'
					local vd `"`vd'`w' = `wl' ; "'
				}
			}
			putexcel a`row' = "list`k'"
			putexcel b`row' = `"`lb'"'
			putexcel c`row' = `n`k''
			putexcel d`row' = (cond(`n`k''>0, "Oui", "Non (0 cas -> pas d'onglet)"))
			putexcel e`row' = "`typ'"
			putexcel f`row' = `"`vd'"'
		}
		capture putexcel a1:a`=$nflags+1', colwidth(16)
		capture putexcel b1:b`=$nflags+1', colwidth(110) txtwrap
		capture putexcel c1:d`=$nflags+1', colwidth(22)
		capture putexcel e1:e`=$nflags+1', colwidth(36)
		capture putexcel f1:f`=$nflags+1', colwidth(90) txtwrap
		putexcel save
		putexcel clear
		forvalues k = 1/$nflags {
			if `n`k'' > 0 {
				local f ${flag`k'}
				local keepv ""
				foreach w in `idvars' `f' ${fvars`k'} {
					capture confirm variable `w'
					if _rc==0 local keepv `keepv' `w'
				}
				local keepv : list uniq keepv
				preserve
					keep if `f' > 0 & !missing(`f')
					keeporder `keepv'
					export excel using "`using'", firstrow(variable) sheet("list`k'", modify)
				restore
			}
		}
		* ---- Onglet "corrections terrain" : UNE LIGNE PAR ANOMALIE PRECISE (variable, libellé, valeur, règle) ----
		if ${ctl_np} > 0 {
			preserve
				clear
				forvalues p = 1/${ctl_np} {
					quietly append using "$temp/ctl_part`p'.dta"
				}
				capture confirm numeric variable sIq01
				if _rc==0 {
					capture decode sIq01, gen(enqueteur)
					if _rc != 0 gen str30 enqueteur = string(sIq01)
					drop sIq01
				}
				else {
					capture confirm variable sIq01
					if _rc==0 rename sIq01 enqueteur
				}
				rename ctl_valeur valeur_actuelle
				gen str12 correction_faite = ""
				gen str100 remarque_terrain = ""
				local tri ""
				foreach w in enqueteur interview__key menage__id variable {
					capture confirm variable `w'
					if _rc==0 local tri `tri' `w'
				}
				local ord ""
				foreach w in enqueteur interview__key menage__id id_menage variable libelle valeur_actuelle type_anomalie regle correction_faite remarque_terrain {
					capture confirm variable `w'
					if _rc==0 local ord `ord' `w'
				}
				sort `tri'
				order `ord'
				export excel using "`using'", firstrow(variable) sheet("corrections terrain", modify)
			restore
		}
		if "`dico'" != "" {
			preserve
				capture describe, replace clear
				if _rc != 0 capture describe, replace
				capture confirm variable varlab
				if _rc==0 {
					keep name varlab
					rename name variable
					rename varlab libelle
					export excel using "`using'", firstrow(variable) sheet("dictionnaire variables", modify)
				}
			restore
		}
	end


/*==============================================================================
================================================================================
	 PARTIE I : APUREMENT DE LA BASE MENAGE (FICHE DE DENOMBREMENT)
================================================================================
===============================================================================*/

/*=========================================================================================
	I.1 - IMPORTATION DE LA BASE BRUTE "FICHE DE DENOMBREMENT"
===========================================================================================*/

	use "$repertoire/ESTDAO_BF.dta", clear
	
	gen long ligne_base_denombrement = _n
	label variable ligne_base_denombrement "N° de ligne dans le fichier brut (Excel : +1 pour la ligne réelle, à cause de l'en-tête)"

	save "$brute/ESTDAO_BF.dta", replace
	use "$brute/ESTDAO_BF.dta", clear

/*=========================================================================================
	I.1 - LABELLISATION DES VARIABLES DE LA FICHE DE DENOMBREMENT
===========================================================================================*/

	* ---------- Bloc ZD / identification ----------
	capture label variable s1q01A			"N° séquentiel"
	capture label variable s0q00			"N° de la ZD (RGPH)"
	* ABSENTE de cet export : num_concession ("N° d'ordre séquentiel automatique des concessions")
	capture label variable s1q01B			"Numéro séquentiel du ménage dans la ZD/grappe"	
	capture label variable s0q01			"Région"			
	capture label variable s0q02			"Province"
	capture label variable s0q03_label		"Libellé de la commune/arrondissement"	
	capture label variable s0q04			"Village/Secteur"	
	capture label variable s1q05			"Milieu de résidence"
	capture label variable type_zd			"Type de la ZD"
	capture label variable nb_menages_rgph	"Nombre de ménages au RGPH"
	capture label variable strate_enquete	"Strate"
	capture label variable statut_zd		"Statut de la ZD (titulaire/remplaçant)"
	capture label variable sIq01			"Enquêteur"
	capture label variable sIq02			"Chef d'équipe"
	capture label variable sIq03			"Date de début de collecte"
	
	capture label variable idConcession	"Identifiant marqué sur la structure/concession (généré par le système)"

	* ---------- Bloc A : dénombrement des concessions/ménages ----------
	capture label variable a01				"A1. Statut de résidence de la structure/concession"
	capture label variable a00a			"A00a. Statut d'occupation de l'habitat du ménage"
	capture label variable a04				"A4. Nom et prénom(s) du chef de concession"
	capture label variable a02b			"N° du logement/ménage dans la concession (saisi par l'enquêteur)"
	capture label variable a03				"A3. Type de ménage dans cette concession"
	label variable a05						"A5. Nom et Prénom(s) du chef de ménage"
	capture label variable a06				"A6. Le ménage abrite-t-il au moins un(e) TD ?"
	label variable a07						"A7. Combien de TD y travaillent"
	capture label variable a08				"A8. Lien de parenté du répondant avec le chef de ménage"
	label variable a09						"A9. Taille du ménage"
	capture label variable a10				"A10. Âge du répondant"
	label variable a11a					"A11a. Premier contact téléphonique du CM"
	capture label variable a11b			"A11b. Deuxième contact téléphonique du CM"
	capture label variable a15				"A15. Observations/remarques sur le ménage"


/*=========================================================================================
	I.2 - LABELS DE VALEURS (MODALITES) DE LA FICHE DE DENOMBREMENT
===========================================================================================*/

	
	foreach v in a01 a00a a03 a06 a08 a09 s0q01 s0q02 s1q05 strate_enquete statut_zd sIq01 sIq02 visa_tirage {
		capture confirm numeric variable `v'
		if _rc!=0 {
			di as error "ATTENTION : `v' n'est pas numérique ou est absent -- vérifiez le dictionnaire de variables (destring/label manuels peut-être nécessaires)."
		}
	}

	save "$brute/base_denombrement_labellisee.dta", replace


/*=========================================================================================
	I.3 - CONSTRUCTION DE L'IDENTIFIANT MENAGE
===========================================================================================*/

	gen id_menage = trim(itrim(idConcession))
	label variable id_menage "Identifiant unique du ménage (= idConcession, généré par Survey Solutions)"

	* Contrôle de conformité du format attendu : "ESTDAOBF/..." ;
	gen erreur_format_id_menage = !regexm(id_menage, "^ESTDAOBF/[0-9]+/[0-9]+/[0-9]+/[0-9]+$")
	label variable erreur_format_id_menage "Anomalie : id_menage ne respecte pas le format attendu (ESTDAOBF/ZD/n° RGPH/enquêteur/n° concession, chiffres uniquement ; le suffixe /NH = habitat non habité n'est pas attendu ici)"


/*=========================================================================================
	I.4 - CONTROLE D'UNICITE ET DETECTION DES ERREURS PROBABLES (base ménage)
===========================================================================================*/

	duplicates report id_menage
	duplicates tag id_menage, gen(doublon_menage)
	label variable doublon_menage "1+ si l'identifiant du ménage est en doublon"

	* -- Nombre de TD hors plage plausible (NSP=-9999 exclu du contrôle)
	gen erreur_horsplage_td = (a07>10 & a07!=-9999 & !missing(a07))
	label variable erreur_horsplage_td "Anomalie : nombre de TD déclaré supérieur à 10 (à vérifier)"

	* -- Taille du ménage manquante ou hors plage plausible (1 à 30) ; NSP exclu
	gen erreur_taille_menage = (missing(a09) | (!inrange(a09,1,30) & a09!=-9999))
	label variable erreur_taille_menage "Anomalie : taille du ménage manquante ou hors plage (1-30)"

	* -- NOUVEAU : trace des "Ne sait pas" (-9999), pour suivi sans les compter en erreur
	gen nsp_a07 = (a07==-9999)
	gen nsp_a09 = (a09==-9999)
	* nsp_a10 RETIRE (test) : a10 absente -- réactivez avec erreur_age_repondant ci-dessus.
	label variable nsp_a07 "A7 codé -9999 (Ne sait pas)"
	label variable nsp_a09 "A9 codé -9999 (Ne sait pas)"

/*=========================================================================================
	I.4b - CONTROLES COMPLEMENTAIRES SUR LA BASE MENAGE (NOUVEAU)
	
	Les variables absentes d'un export sont ignorées (listées dans $ctl_absentes).
===========================================================================================*/

	global ctl_keyvars "ligne_base_denombrement interview__key id_menage s0q01 s0q02 s0q03_label s0q04 sIq01"
	ctl_init

	local provinces 101 102 103 201 202 203 204 301 302 401 402 403 501 601 602 603 701 702 703 801 802 803 901 902 903 904 1001 1002 1003 1101 1102 1103 1201 1202 1301 1302 1401 1402 1501 1502 1601 1602 1603 1701 1702 1703 1704

	* -- Variables d'identification : renseignées + modalités valides (codes du questionnaire)
	ctl_q s1q01p, si(!missing(s1q01p)) codes(1/5)
	ctl_q s1q01A, si(1==1)
	ctl_q s0q00, si(1==1)
	ctl_q s0q01, si(1==1) codes(1/17)
	ctl_q s0q02, si(1==1) codes(`provinces')
	ctl_q s1q05, si(1==1) codes(1/2)
	ctl_q strate_enquete, si(1==1) codes(1/3)
	ctl_q statut_zd, si(1==1) codes(1/2)
	ctl_q statut, si(1==1) codes(1/2)
	ctl_q nb_menages_rgph, si(1==1) plage(1 1000000)
	ctl_q idConcession, si(1==1)
	ctl_q a05, si(1==1)
	ctl_q a11a, si(1==1)
	ctl_q sIq01, si(1==1) codes(1/20)
	ctl_q sIq02, si(1==1) codes(1/5)
	ctl_q sIq03, si(1==1)
	ctl_q autorisation_debut, si(1==1) codes(1/2)
	ctl_q hr, si(1==1) codes(1/5)
	ctl_q hr_autres, si(hr==5)
	ctl_q sIq05, si(1==1) codes(1/14)
	ctl_q sIq06, si(1==1) codes(1/3)
	ctl_q sIq07, si(inlist(interview__status,100,120,130))

	* -- Région / province, strate / province
	gen byte erreur_region_province = (!missing(s0q01) & !missing(s0q02) & floor(s0q02/100) != s0q01)
	label variable erreur_region_province "Anomalie : la province (s0q02) n'appartient pas à la région (s0q01)"

	gen byte alerte_strate_province = 0
	replace alerte_strate_province = 1 if !missing(strate_enquete) & !missing(s0q02) & !((strate_enquete==1 & s0q02==501) | (strate_enquete==2 & s0q02==401) | (strate_enquete==3 & s0q02==1703))
	label variable alerte_strate_province "ALERTE : strate (Ouaga/Bobo/Ouahigouya) non cohérente avec la province (Kadiogo/Houet/Yatenga)"

	* -- idConcession : format complet et cohérence avec la ZD (s1q01A) et le n° de ZD RGPH (s0q00)
	capture tostring s0q00, replace	// s0q00 doit être du texte pour la comparaison ci-dessous (sans effet s'il l'est déjà)
	gen str20 ctl_id_zd = ""
	gen str20 ctl_id_rgph = ""
	replace ctl_id_zd   = regexs(1) if regexm(id_menage, "^ESTDAOBF/([0-9]+)/([0-9]+)/([0-9]+)/([0-9]+)$")
	replace ctl_id_rgph = regexs(2) if regexm(id_menage, "^ESTDAOBF/([0-9]+)/([0-9]+)/([0-9]+)/([0-9]+)$")
	gen byte erreur_id_composants = 0
	replace erreur_id_composants = 1 if ctl_id_zd!="" & !missing(s1q01A) & (ctl_id_zd != string(s1q01A) | ctl_id_rgph != trim(s0q00))
	label variable erreur_id_composants "Anomalie : composantes de id_menage (ZD, n° RGPH) différentes de s1q01A / s0q00"

	* -- Téléphone du chef de ménage : 8 chiffres groupés par 2 (99 99 99 99 = pas de numéro ; 00 00 00 00 = ne sait pas)
	gen byte erreur_tel_cm = (trim(a11a)!="" & !regexm(trim(a11a), "^[0-9][0-9] [0-9][0-9] [0-9][0-9] [0-9][0-9]$"))
	label variable erreur_tel_cm "Anomalie : format du téléphone du CM (a11a) invalide (attendu : 8 chiffres par groupes de 2)"

	* -- A7 / A9
	gen byte erreur_a07_invalide = (!missing(a07) & a07<1 & a07!=-9999)
	label variable erreur_a07_invalide "Anomalie : nombre de TD (a07) inférieur à 1 (hors NSP = -9999)"
	gen byte erreur_a07_sup_a09 = (!missing(a07) & !missing(a09) & a07!=-9999 & a09!=-9999 & a07>a09)
	label variable erreur_a07_sup_a09 "Anomalie : nombre de TD (a07) supérieur à la taille du ménage (a09)"

	* -- Roster du ménage (smq01__0 ... smq01__19) : nombre de noms saisis
	gen int nb_noms_roster_estdao = 0
	forvalues k = 0/19 {
		capture confirm variable smq01__`k'
		if _rc==0 quietly replace nb_noms_roster_estdao = nb_noms_roster_estdao + 1 if trim(smq01__`k')!="" & trim(smq01__`k')!="##N/A##"
	}
	label variable nb_noms_roster_estdao "Nombre de noms saisis dans le roster du ménage (fichier ménage)"

	gen byte erreur_roster_vide = (autorisation_debut==1 & nb_noms_roster_estdao==0)
	label variable erreur_roster_vide "Anomalie : autorisation de commencer = Oui mais aucun membre dans le roster"
	gen byte erreur_roster_sup_taille = (!missing(a09) & a09!=-9999 & nb_noms_roster_estdao>a09)
	label variable erreur_roster_sup_taille "Anomalie : plus de membres dans le roster que la taille du ménage déclarée (a09)"
	gen byte erreur_hr_incoherent = ((autorisation_debut==2 & nb_noms_roster_estdao>0) | (hr==1 & nb_noms_roster_estdao==0) | (inlist(hr,3,4) & nb_noms_roster_estdao>0))
	label variable erreur_hr_incoherent "Anomalie : résultat de l'enquête ménage (hr) / autorisation incompatible avec le roster"

	gen byte alerte_sIq06_vs_hr = ((sIq06==1 & inlist(hr,2,3,4)) | (sIq06==3 & nb_noms_roster_estdao>0))
	label variable alerte_sIq06_vs_hr "ALERTE : résultat du questionnaire (sIq06) non cohérent avec le résultat ménage (hr)"

	* -- Le 1er membre du roster doit être le chef de ménage (a05) : comparaison souple (3 premières lettres d'un des 2 premiers mots)
	gen byte alerte_chef_vs_roster = 0
	capture confirm variable smq01__0
	if _rc==0 {
		gen str100 ctl_chef = lower(itrim(trim(a05)))
		gen str100 ctl_r0   = lower(itrim(trim(smq01__0)))
		gen str30 ctl_m1 = substr(word(ctl_chef,1),1,3)
		gen str30 ctl_m2 = substr(word(ctl_chef,2),1,3)
		replace alerte_chef_vs_roster = 1 if ctl_chef!="" & ctl_r0!="" & !((ctl_m1!="" & strpos(ctl_r0, ctl_m1)>0) | (ctl_m2!="" & strpos(ctl_r0, ctl_m2)>0))
	}
	label variable alerte_chef_vs_roster "ALERTE : 1er membre du roster (smq01__0) différent du chef de ménage (a05)"

	* -- Dates de début / fin de collecte
	gen double ctl_c03 = clock(substr(sIq03,1,10) + " " + substr(sIq03,12,8), "YMDhms")
	gen double ctl_c07 = clock(substr(sIq07,1,10) + " " + substr(sIq07,12,8), "YMDhms")
	gen byte erreur_date_invalide = ((trim(sIq03)!="" & missing(ctl_c03)) | (trim(sIq07)!="" & missing(ctl_c07)))
	label variable erreur_date_invalide "Anomalie : date de début (sIq03) ou de fin (sIq07) de collecte illisible"
	gen byte erreur_fin_avant_debut = (!missing(ctl_c03) & !missing(ctl_c07) & ctl_c07 < ctl_c03)
	label variable erreur_fin_avant_debut "Anomalie : date de fin de collecte (sIq07) antérieure à la date de début (sIq03)"

	gen byte alerte_erreurs_serveur = 0
	capture confirm variable has__errors
	if _rc==0 replace alerte_erreurs_serveur = (has__errors>0 & !missing(has__errors))
	label variable alerte_erreurs_serveur "ALERTE : l'entretien contient des erreurs de validation non résolues (has__errors > 0)"

	* -- Enregistrement des listings (ordre = numéro d'onglet)
	global nflags 0
	addflag doublon_menage "id_menage" "1+ si l'identifiant du ménage est en doublon"
	addflag erreur_format_id_menage "id_menage" "Anomalie : id_menage ne respecte pas le format attendu (ESTDAOBF/ZD/n° RGPH/enquêteur/n° concession, chiffres uniquement ; le suffixe /NH = habitat non habité n'est pas attendu ici)"
	addflag erreur_horsplage_td "a07" "Anomalie : nombre de TD déclaré supérieur à 10 (à vérifier)"
	addflag erreur_taille_menage "a09" "Anomalie : taille du ménage manquante ou hors plage (1-30)"
	addflag erreur_id_composants "id_menage s1q01A s0q00" "Anomalie : composantes de id_menage (ZD, n° RGPH) différentes de s1q01A / s0q00"
	addflag erreur_region_province "s0q01 s0q02" "Anomalie : la province (s0q02) n'appartient pas à la région (s0q01)"
	addflag erreur_a07_invalide "a07" "Anomalie : nombre de TD (a07) inférieur à 1 (hors NSP = -9999)"
	addflag erreur_a07_sup_a09 "a07 a09" "Anomalie : nombre de TD (a07) supérieur à la taille du ménage (a09)"
	addflag erreur_tel_cm "a11a" "Anomalie : format du téléphone du CM (a11a) invalide (attendu : 8 chiffres par groupes de 2)"
	addflag erreur_roster_vide "autorisation_debut nb_noms_roster_estdao" "Anomalie : autorisation de commencer = Oui mais aucun membre dans le roster"
	addflag erreur_roster_sup_taille "a09 nb_noms_roster_estdao" "Anomalie : plus de membres dans le roster que la taille du ménage déclarée (a09)"
	addflag erreur_hr_incoherent "autorisation_debut hr nb_noms_roster_estdao" "Anomalie : résultat de l'enquête ménage (hr) / autorisation incompatible avec le roster"
	addflag erreur_date_invalide "sIq03 sIq07" "Anomalie : date de début (sIq03) ou de fin (sIq07) de collecte illisible"
	addflag erreur_fin_avant_debut "sIq03 sIq07" "Anomalie : date de fin de collecte (sIq07) antérieure à la date de début (sIq03)"
	addflag erreur_manq_oblig "liste_manq_oblig" "Anomalie : nb de questions POSEES mais non renseignées (détail variable par variable dans l'onglet 'corrections terrain')"
	addflag erreur_hors_filtre "liste_hors_filtre" "Anomalie : nb de questions renseignées alors qu'elles NE DEVAIENT PAS être posées (détail dans l'onglet 'corrections terrain')"
	addflag erreur_modalite "liste_modalite" "Anomalie : nb de modalités/valeurs incorrectes (détail dans l'onglet 'corrections terrain')"
	addflag alerte_strate_province "strate_enquete s0q02" "ALERTE : strate (Ouaga/Bobo/Ouahigouya) non cohérente avec la province (Kadiogo/Houet/Yatenga)"
	addflag alerte_chef_vs_roster "a05 smq01__0" "ALERTE : 1er membre du roster (smq01__0) différent du chef de ménage (a05)"
	addflag alerte_sIq06_vs_hr "hr sIq06 nb_noms_roster_estdao" "ALERTE : résultat du questionnaire (sIq06) non cohérent avec le résultat ménage (hr)"
	addflag alerte_erreurs_serveur "has__errors" "ALERTE : l'entretien contient des erreurs de validation non résolues (has__errors > 0)"

	di as text "Variables / conditions non évaluées (absentes de la base ménage) : ${ctl_absentes}"

	egen nb_anomalies_menage = rowtotal(erreur_*)
	label variable nb_anomalies_menage "Nombre total d'anomalies détectées pour le ménage"
	egen nb_alertes_menage = rowtotal(alerte_*)
	label variable nb_alertes_menage "Nombre d'alertes (à vérifier, non comptées comme anomalies)"

	gen statut_controle_menage = "🟢 Normal"
	replace statut_controle_menage = "🟡 Alerte(s) à vérifier" if nb_alertes_menage>=1
	replace statut_controle_menage = "🟠 A surveiller" if nb_anomalies_menage>=1 & nb_anomalies_menage<=2
	replace statut_controle_menage = "🔴 A corriger"    if nb_anomalies_menage>=3
	label variable statut_controle_menage "Statut de contrôle qualité du ménage"

	save "$temp/base_menage_avec_indicateurs.dta", replace


/*=========================================================================================
	I.5 - EXPORT DES LISTINGS D'ERREURS (BASE MENAGE) VERS EXCEL
	(export générique : 1 onglet par indicateur ayant des cas + onglet "description" + dictionnaire)
===========================================================================================*/

	use "$temp/base_menage_avec_indicateurs.dta", clear

	ctl_export using "$listing/listing erreurs fiche denombrement.xlsx", ///
		idvars(ligne_base_denombrement interview__key id_menage s0q01 s0q02 s0q03_label s0q04 s1q01A sIq01 nb_anomalies_menage nb_alertes_menage statut_controle_menage) dico

/*=========================================================================================
	I.6 - SAUVEGARDE DE LA BASE MENAGE APUREE
===========================================================================================*/

	use "$temp/base_menage_avec_indicateurs.dta", clear

	capture drop erreur_*
	capture drop alerte_*
	capture drop info_*
	capture drop liste_*
	capture drop ctl_*
	drop doublon_menage nsp_a07 nsp_a09 nb_alertes_menage	// nsp_a10 retiré : a10 absente de cet export
	save "$sortie/base_denombrement_apuree.dta", replace


/*==============================================================================
================================================================================
	 PARTIE II : APUREMENT DE LA BASE INDIVIDU (QUESTIONNAIRE MENAGE + TD)
================================================================================
===============================================================================*/

/*=========================================================================================
	II.1 - IMPORTATION DE LA BASE BRUTE "QUESTIONNAIRE MENAGE / TD"
===========================================================================================*/

	use "$repertoire/menage.dta", clear	// à utiliser à la place si vous disposez du .dta natif (comme pour la Partie I)

	gen long ligne_base_questionnaire = _n
	label variable ligne_base_questionnaire "N° de ligne dans le fichier brut (Excel : +1 pour la ligne réelle, à cause de l'en-tête)"

	save "$brute/menage.dta", replace
	use "$brute/menage.dta", clear


/*=========================================================================================
	II.2 - TABLE DE CORRESPONDANCE (uniquement si vos noms de colonnes brutes diffèrent)
===========================================================================================*/

	capture confirm variable id_menage
	if _rc!=0 {
		capture confirm variable idConcession
		if _rc==0 rename idConcession id_menage
		else gen id_menage = interview__id
	}
	capture confirm variable id_quest
	if _rc!=0 {
		gen id_quest = interview__id + "_" + string(menage__id)	// identifiant unique par membre du ménage (interview + n° d'ordre dans le roster)
	}

	capture confirm file "$brute/ESTDAO_BF.dta"
	if _rc==0 {
		merge m:1 interview__id using "$brute/ESTDAO_BF.dta", ///
			keepusing(idConcession sIq01 sIq02 sIq03 sIq07 s0q01 s0q02 s0q03_label s0q04 s1q05 hr autorisation_debut sIq06) ///
			generate(ctl_merge_est) keep(master match)
		sort ligne_base_questionnaire
		replace id_menage = trim(itrim(idConcession)) if trim(idConcession)!=""
	}
	else {
		gen byte ctl_merge_est = 3
	}



/*=========================================================================================
	II.3 - LABELLISATION DES VARIABLES (par partie du questionnaire)
===========================================================================================*/

	* ---------- Identification / roster ménage ----------
	capture label variable id_quest		"Identifiant unique du questionnaire individu"
	capture label variable id_menage		"Identifiant du ménage (= idConcession, lien avec la fiche de dénombrement)"
	capture label variable sIq01			"Nom et prénom(s) de l'enquêteur"
	capture label variable sIq03			"Date de début de collecte"
	label variable smq01					"Nom et prénom(s) du membre du ménage"
	label variable smq02					"Sexe du membre"
	label variable smq03a					"Jour de naissance"
	label variable smq03b					"Mois de naissance"
	label variable smq03c					"Annee de naissance"
	label variable smq03d					"Age approximatif"
	label variable jour_nais				"Jour de naissance imputé"
	label variable mois_nais				"Mois de naissance impute"
	label variable annee_naiss				"Annee de naissance imputée"	
	label variable smq04					"Âge calculé du membre"
	label variable smq05					"Niveau d'études le plus élevé (si âge>=5 ans)"
	label variable smq06					"Statut matrimonial (si âge>=15 ans)"
	label variable smq07					"Est un(e) travailleur/travailleuse domestique (si âge>=10 ans)"
	capture label variable hr						"Résultat de l'enquête ménage"	// CORRECTION : "hr" est absente de cet export "menage.dta" (à vérifier auprès de qui gère l'export Survey Solutions)
	label variable td01					"Date de début de l'entretien TD"
	label variable consentement_td			"Consentement de la TD à poursuivre l'entretien"
	label variable td02					"Résultat de l'enquête TD"

	* ---------- Partie 1 : Informations générales ----------
	capture label variable s1q01p					"1a. Pays d'origine"	// CORRECTION : "s1q01p" est absente de cet export (seule "s1q01", la localité, existe) -- le pays d'origine n'est pas collecté ici, ou pas sous ce nom
	label variable s1q01					"1b. Localite de provenance"
	label variable s1q02					"2. Âge (tranche)"
	label variable s1q03					"3. Statut matrimonial"
	label variable s1q04					"4. Niveau d'éducation en français"
	capture label variable s1q05					"5. Milieu de résidence (couverture du ménage)"	// CORRECTION : absente de "menage.dta" -- cohérent avec la note en tête de fichier (s1q05 est un attribut de la fiche de dénombrement/COUVERTURE, à récupérer par fusion en Partie III, pas dans ce fichier)
	label variable s1q06					"6. Mécanisme de placement pour l'emploi actuel"
	label variable s1q06_autre				"6. Mécanisme de placement : précision (Autre)"
	label variable s1q07_autre				"7. Type de travail : précision (Autre)"
	forvalues k = 1/6 {
		capture confirm variable s1q07__`k'
		if _rc==0 label variable s1q07__`k' "7. Type de travail domestique : modalité `k'"
	}

	* ---------- Partie 2 : Conditions de travail ----------
	label variable s2q01					"8. Heures travaillées en moyenne par jour"
	label variable s2q02					"9. Heure de début du travail"
	label variable s2q03					"10. Heure de fin du travail"
	label variable s2q04					"11. Temps de repos pris au cours de la journée"
	label variable s2q05					"12. A un contrat de travail écrit"
	label variable s2q06					"13. Si non, raison de l'absence de contrat"
	label variable s2q06_autres			"13. Précision (Autre)"
	label variable s2q06a					"13a. Nature du paiement (en nature/en espèces/les deux)"
	label variable s2q07					"14. Payée de manière régulière (si paiement en espèces)"
	label variable s2q08					"15. Montant moyen du salaire mensuel"
	label variable s2q09					"16. Mode de perception du salaire"
	label variable s2q09_autre				"16. Précision (Autre)"
	label variable s2q10					"17. A des jours de repos"
	label variable s2q11					"18. Si non, raison de l'absence de repos"
	label variable s2q11_autre				"18. Précision (Autre)"
	label variable s2q12					"19. Si oui, les jours de repos sont-ils payés"
	label variable s2q13					"20. Bénéficie d'un congé maladie rémunéré"
	label variable s2q14					"21. Si non, raison de l'absence de congé maladie"
	label variable s2q14_autre				"21. Précision (Autre)"
	label variable s2q17					"24. Accès à un logement fourni par l'employeur"
	label variable s2q18					"25. Environnement de travail sain et sécurisé"
	label variable s2q19					"26. Porte des objets très lourds"
	label variable s2q20					"27. Utilise des objets tranchants"
	label variable s2q21					"28. Utilise des appareils électriques à risque"
	label variable s2q22					"29. Utilise d'autres objets dangereux"
	label variable s2q22_precision			"29. Précision"
	label variable s2q23					"30. Utilise des produits chimiques de nettoyage"
	label variable s2q24					"31. Utilise des produits inflammables"
	label variable s2q25					"32. Utilise des produits toxiques"
	label variable s2q26					"33. Utilise des produits allergènes"
	label variable s2q27					"34. Utilise des produits corrosifs"
	label variable s2q28					"35. Utilise d'autres produits dangereux"
	label variable s2q28_precision			"35. Précision"
	label variable s2q29					"36. Utilise des gants de protection"
	label variable s2q30					"37. Utilise un masque de protection"
	label variable s2q31					"38. Utilise des lunettes de protection"
	label variable s2q32					"39. Utilise un tablier ou tenue adaptée"
	label variable s2q33					"40. Utilise d'autres équipements de protection"
	label variable s2q34					"41. Espace de travail bien aéré"
	label variable s2q35					"42. Espace de travail bien éclairé"
	capture label variable s2q15_autre				"22. Violences : précision (Autre)"	// CORRECTION : absente de la base (Q22 n'a pas de modalité "Autre" à préciser dans cet export)
	label variable s2q16_autre				"23. Auteur des violences : précision (Autre)"
	forvalues k = 1/4 {
		capture confirm variable s2q15__`k'
		if _rc==0 label variable s2q15__`k' "22. Violences subies : modalité `k' (1=phys.,2=verb.,3=morale,4=privation nourriture)"
	}
	forvalues k = 1/4 {
		capture confirm variable s2q16__`k'
		if _rc==0 label variable s2q16__`k' "23. Auteur des violences : modalité `k'"
	}

	* ---------- Partie 3 : Santé et bien-être ----------
	label variable s3q01					"43. Victime d'un accident de travail"
	label variable s3q02_autre				"44. Nature de l'accident : précision (Autre)"
	forvalues k = 1/7 {
		capture confirm variable s3q02__`k'
		if _rc==0 label variable s3q02__`k' "44. Nature de l'accident : modalité `k' (7=Autre, 6=Accident de trajet [NOUVEAU])"
	}
	label variable s3q03					"45. A des problèmes de santé liés au travail"
	label variable s3q04_autre				"46. Problèmes de santé : précision (Autre)"
	forvalues k = 1/8 {
		capture confirm variable s3q04__`k'
		if _rc==0 label variable s3q04__`k' "46. Problème de santé : modalité `k'"
	}
	label variable s3q05					"47. A déjà consulté un professionnel de santé"
	label variable s3q06					"48. Type de soins reçus"
	label variable s3q06_autre				"48. Précision (Autre)"
	label variable s3q07					"49. Difficultés d'accès aux soins médicaux"
	label variable s3q08_autre				"50. Raisons des difficultés : précision (Autre)"
	forvalues k = 1/5 {
		capture confirm variable s3q08__`k'
		if _rc==0 label variable s3q08__`k' "50. Raison de la difficulté d'accès : modalité `k'"
	}
	label variable s3q09					"51. Déclarée à une assurance/mutuelle maladie"
	label variable s3q10					"52. Si non, pourquoi"
	label variable s3q10_autre				"52. Précision (Autre)"
	label variable s3q11					"53. Accès à des soins gratuits/subventionnés par l'Etat"
	label variable s3q12					"54. Prise en charge par l'employeur en cas de maladie (si Q53=Non)"
	label variable s3q13					"55. Soutenue financièrement (famille/amis) en cas de maladie"
	label variable s3q14					"56. Déjà victime de discrimination dans un établissement de santé"

	* ---------- Partie 4 : Santé mentale et bien-être psychologique ----------
	label variable s4q01					"57. Fréquence de tristesse persistante"
	label variable s4q02					"58. Fréquence de stress au travail"
	label variable s4q03					"59. Difficultés à dormir liées au travail"
	label variable s4q04					"60. Soutenue socialement (famille/amis/confidents)"
	label variable s4q05					"61. Accès à un soutien psychologique"
	label variable s4q06					"62. Satisfaite de sa qualité de vie"

	* ---------- Partie 5 : Santé de la reproduction (TD de sexe féminin uniquement) ----------
	label variable s5q01					"63. Accès à des services de santé reproductive"
	label variable s5q02					"64. Si non, pourquoi"
	label variable s5q02_autre				"64. Précision (Autre)"
	label variable s5q03					"65. Où consulter en cas de besoin"
	label variable s5q03_autre				"65. Précision (Autre)"
	label variable s5q04					"66. A déjà effectué une consultation gynécologique"
	label variable s5q05					"67. Si non, pourquoi"
	label variable s5q05_autre				"67. Précision (Autre)"
	label variable s5q06					"68. A déjà été enceinte"
	label variable s5q07					"69. Nombre de grossesses (catégoriel, 6=Plus de 5)"
	label variable s5q07_autre				"69. Nombre précis de grossesses (si Q69=Plus de 5)"
	label variable s5q08					"70. Lieu d'accouchement"
	label variable s5q08_autre				"70. Précision (Autre)"
	label variable s5q09					"71. Accès à des protections menstruelles"
	label variable s5q10					"72. Si non, principale difficulté"
	label variable s5q10_autre				"72. Précision (Autre)"
	label variable s5q11					"73. Victime de discrimination liée à la grossesse"
	label variable s5q12					"74. Bénéficie d'un congé de maternité rémunéré"

	* ---------- Partie 6 : Accès aux services sociaux et légaux ----------
	label variable s6q01					"75. Connaît ses droits en tant que TD"
	label variable s6q02					"76. A déjà tenté de faire valoir ses droits"
	label variable s6q03					"77. Connaît des organisations de défense des droits des TD"
	label variable s6q04					"78. Jugement sur les interventions de ces organisations"
	label variable s6q05_autre				"79. Suggestions : précision (Autre)"
	label variable s6q06_autre				"80. Attentes envers l'Etat : précision (Autre)"
	label variable s6q07					"81. Intérêt pour une formation sur les droits et l'accès aux soins"
	forvalues k = 1/5 {
		capture confirm variable s6q05__`k'
		if _rc==0 label variable s6q05__`k' "79. Suggestion : modalité `k'"
	}
	forvalues k = 1/7 {
		capture confirm variable s6q06__`k'
		if _rc==0 label variable s6q06__`k' "80. Attente envers l'Etat : modalité `k'"
	}

	* ---------- Partie 7 : Informations complémentaires ----------
	label variable s7q01					"82. Suggestions libres pour améliorer les conditions de santé/travail"

	* ---------- Partie 8 : Effectivité des agences de placement ----------
	label variable s8q01					"83. A entendu parler d'une agence de placement de TD"
	label variable s8q02					"84. A déjà bénéficié de l'appui d'une agence de placement"
	label variable s8q03_autre				"85. Type d'appui : précision (Autre)"
	label variable s8q04					"86. Satisfaite de l'appui reçu des agences de placement"
	label variable s8q05_autre				"87. Si non, raison de l'insatisfaction : précision (Autre)"
	forvalues k = 1/7 {
		capture confirm variable s8q03__`k'
		if _rc==0 label variable s8q03__`k' "85. Type d'appui reçu : modalité `k'"
	}
	forvalues k = 1/5 {
		capture confirm variable s8q05__`k'
		if _rc==0 label variable s8q05__`k' "87. Raison de l'insatisfaction : modalité `k'"
	}

	* ---------- Partie 9 : Effectivité des institutions d'appui ----------
	label variable s9q01					"88. Connaît des institutions chargées de protéger les droits des TD"
	label variable s9q02_autre				"89. Institutions connues : précision (Autre)"
	label variable s9q03					"90. A déjà fait l'objet d'un contrôle de l'inspection du travail"
	label variable s9q04					"91. Employeur sanctionné par l'inspection du travail"
	label variable s9q05					"92. Ces institutions interviennent-elles efficacement"
	label variable s9q06					"93. A déjà sollicité l'appui d'une de ces institutions"
	label variable s9q07					"94. Nature de la demande"
	label variable s9q07_autre				"94. Précision (Autre)"
	label variable s9q08					"95. La demande a-t-elle été satisfaite"
	label variable s9q09					"96. Principales raisons des difficultés d'accès"
	label variable s9q09_autre				"96. Précision (Autre)"
	forvalues k = 1/6 {
		capture confirm variable s9q02__`k'
		if _rc==0 label variable s9q02__`k' "89. Institution connue : modalité `k'"
	}


/*=========================================================================================
	II.4 - LABELS DE VALEURS (MODALITES) DU QUESTIONNAIRE
===========================================================================================*/

	#delimit ;

	label define s1q01p_lbl
	1 "Sénégal"
	2 "Côte d'Ivoire"
	3 "Burkina Faso"
	4 "Mauritanie"
	5 "Mali"
	;

	label define s1q02_lbl
	1 "En dessous de 15 ans"
	2 "Entre 15 ans et 18 ans (non révolus)"
	3 "Entre 18 ans et 35 ans"
	4 "35 ans ou plus"
	;

	label define s1q03_lbl
	1 "Célibataire"
	2 "Mariée"
	3 "Divorcée"
	4 "Veuve"
	;

	label define s1q04_lbl
	1 "Aucun/Préscolaire"
	2 "Primaire"
	3 "Post-Primaire"
	4 "Secondaire"
	5 "Supérieur"
	;

	label define s1q06_lbl
	1 "Mise en relation"
	2 "Confiage"
	3 "Porte à porte"
	4 "Parrainage"
	5 "Affichage"
	6 "Souscription à une agence de placement"
	7 "Internet/réseaux sociaux"
	8 "Autre (préciser)"
	;

	label define s2q01_lbl
	1 "Moins de 8 heures"
	2 "8 heures"
	3 "Plus de 8 heures"
	;

	label define s2q02_lbl
	1 "Avant 5 heures"
	2 "5 heures"
	3 "6 heures"
	4 "7 heures"
	5 "8 heures"
	6 "Après 8 heures"
	;

	label define s2q03_lbl
	1 "Avant 17 heures"
	2 "17 heures"
	3 "18 heures"
	4 "19 heures"
	5 "20 heures"
	6 "Après 20 heures"
	;

	label define s2q04_lbl
	1 "Moins de 30 mn"
	2 "Entre 30mn et 1h"
	3 "Entre 1h et 1h30mn"
	4 "Entre 1h30mn et 2h"
	5 "Plus de 2 heures"
	;

	label define s2q06_lbl
	1 "Refus de l'employeur"
	2 "Non connaissance des droits"
	3 "Autre (préciser)"
	;

	* NOUVEAU (Q13a) ;
	label define s2q06a_lbl
	1 "En nature"
	2 "En espèces"
	3 "Les deux"
	;

	label define s2q07_lbl
	1 "Oui"
	2 "Non"
	3 "Parfois"
	;

	label define s2q08_lbl
	1 "Moins de 15 000 FCFA"
	2 "15 000 - 25 000 FCFA"
	3 "25 000 - 50 000 FCFA"
	4 "50 000 - 75 000 FCFA"
	5 "Plus de 75 000 FCFA"
	;

	* MODIFIE : "Mobile money" fait officiellement partie de la modalité 5 ;
	label define s2q09_lbl
	1 "Main à main"
	2 "Virement à une agence de placement"
	3 "Via les parents"
	4 "Virement bancaire"
	5 "Mobile money"
	6 "Autre (préciser)"
	;

	label define s2q12_lbl
	1 "Payés"
	2 "Non payés (défalqués du salaire)"
	;

	label define s2q13_lbl
	1 "Oui, payé"
	2 "Oui, mais non payé"
	3 "Non"
	;

	label define s3q06_lbl
	1 "Soins médicaux (médecin généraliste)"
	2 "Soins psychologiques"
	3 "Soins de physiothérapie"
	4 "Autre (préciser)"
	;

	label define s3q10_lbl
	1 "Refus de l'employeur"
	2 "Non connaissance de la procédure"
	3 "Non assistance"
	4 "Autre (préciser)"
	;

	label define s4q01_lbl
	1 "Tous les jours"
	2 "Quelques jours"
	3 "Rarement"
	4 "Jamais"
	;

	label define s4q02_lbl
	1 "Tous les jours"
	2 "Quelques jours par semaine"
	3 "Rarement"
	4 "Jamais"
	;

	label define s4q03_lbl
	1 "Oui, souvent"
	2 "Parfois"
	3 "Rarement"
	4 "Jamais"
	;

	label define s5q02_lbl
	1 "Coût trop élevé"
	2 "Tabous"
	3 "Restrictions imposées par l'employeur"
	4 "Eloignement du centre de santé"
	5 "Autre (préciser)"
	;

	label define s5q03_lbl
	1 "Hôpital/Centre de santé"
	2 "Tradipraticien"
	3 "Autre (préciser)"
	;

	label define s5q05_lbl
	1 "Coût trop élevé"
	2 "Non accès à un(e) gynécologue"
	3 "Tabous"
	4 "Restrictions imposées par l'employeur"
	5 "Autre (préciser)"
	;

	label define s5q07_lbl
	1 "1"
	2 "2"
	3 "3"
	4 "4"
	5 "5"
	6 "Plus de 5 (préciser)"
	;

	label define s5q08_lbl
	1 "Hôpital/Centre de santé"
	2 "À domicile"
	3 "Autre (préciser)"
	;

	label define s5q10_lbl
	1 "Coût trop élevé"
	2 "Manque d'accès aux produits"
	3 "Tabous"
	4 "Restrictions imposées par l'employeur"
	5 "Autre (préciser)"
	;

	label define s5q12_lbl
	1 "Oui, payé"
	2 "Oui, mais non payé"
	3 "Non"
	;

	label define s6q04_lbl
	1 "Efficaces pour défendre mes droits"
	2 "Améliorations partielles"
	3 "Pas d'impact notable"
	4 "Pas d'améliorations concrètes"
	5 "N'a pas bénéficié directement de leurs interventions"
	;

	label define s9q03_lbl
	1 "Oui, de l'inspection du travail"
	2 "Oui, d'une autre institution"
	3 "Non"
	;

	label define s9q05_lbl
	1 "Oui, de manière efficace"
	2 "Oui, mais avec des limites"
	3 "Non, elles ne sont pas efficaces"
	4 "Je ne sais pas"
	;

	label define s9q07_lbl
	1 "Réclamation pour non-paiement de salaire"
	2 "Régulation du contrat de travail"
	3 "Accès à la protection sociale"
	4 "Protection contre les violences"
	5 "Assistance en cas de conflit avec l'employeur"
	6 "Autre (préciser)"
	;

	label define s9q08_lbl
	1 "Oui"
	2 "Pas totalement"
	3 "Non"
	;

	label define s9q09_lbl
	1 "Manque d'informations sur les voies de recours"
	2 "Difficultés matérielles d'accès (distance, coûts du transport)"
	3 "Procédures complexes"
	4 "Peur de représailles de l'employeur"
	5 "Autre (préciser)"
	;

	#delimit cr

	label define OuiNon 1 "Oui" 2 "Non"

	* --- Application des labels (variables OUI/NON simples) ---------------------------------
	local varlist_ouinon s2q05 s2q10 s2q17 s2q18 s2q19 s2q20 s2q21 s2q22 s2q23 s2q24 s2q25 ///
		s2q26 s2q27 s2q28 s2q29 s2q30 s2q31 s2q32 s2q33 s2q34 s2q35 s3q01 s3q03 s3q05 ///
		s3q07 s3q09 s3q11 s3q12 s3q13 s3q14 s4q04 s4q05 s4q06 s5q01 s5q04 s5q06 s5q09 ///
		s5q11 s6q01 s6q02 s6q03 s6q07 s8q01 s8q02 s8q04 s9q01 s9q04 s9q06
	foreach v of local varlist_ouinon {
		capture confirm variable `v'
		if _rc==0 {
			capture destring `v', replace
			label values `v' OuiNon
		}
	}

	local varlist_specifiques s1q01p s1q02 s1q03 s1q04 s1q06 s2q01 s2q02 s2q03 s2q04 ///
		s2q06 s2q06a s2q07 s2q08 s2q09 s2q12 s2q13 s3q06 s3q10 s4q01 s4q02 s4q03 s5q02 ///
		s5q03 s5q05 s5q07 s5q08 s5q10 s5q12 s6q04 s9q03 s9q05 s9q07 s9q08 s9q09
	foreach v of local varlist_specifiques {
		capture confirm variable `v'
		if _rc==0 {
			capture destring `v', replace
			capture label values `v' `v'_lbl
		}
	}

	capture destring s2q11, replace
	capture label values s2q11 s2q06_lbl
	capture destring s2q14, replace
	capture label values s2q14 s2q06_lbl

	capture destring s5q07_autre, replace force

	save "$brute/base_questionnaire_td_labellisee.dta", replace


/*=========================================================================================
	II.5 - CONTROLES D'ELIGIBILITE ET DE COHERENCE DU FILTRE ROSTER
	(seuls les membres identifiés TD (smq07==1) ET consentants (consentement_td==1)
	 doivent porter des réponses aux parties 1 à 9)
	NB : les indicateurs "detail_*" restent listés (onglets historiques list1 à list23)
	mais ne sont PAS comptés dans nb_anomalies : ils sont déjà couverts par les indicateurs
	génériques erreur_manq_oblig / erreur_hors_filtre / erreur_modalite (II.6b).
===========================================================================================*/

	gen byte ctl_td = (smq07==1 & consentement_td==1)
	label variable ctl_td "Aide : TD identifiée (smq07=1) et consentante (consentement_td=1)"

	gen detail_td_hors_filtre = (smq07!=1 & !missing(s1q02))
	label variable detail_td_hors_filtre "Détail : réponses TD renseignées alors que smq07 != 1 (non identifié TD)"

	gen detail_consentement_manquant = (smq07==1 & missing(consentement_td))
	label variable detail_consentement_manquant "Détail : identifié TD (smq07=1) mais consentement (consentement_td) non renseigné"

	gen detail_refus_avec_reponses = (consentement_td==2 & !missing(s1q02))
	label variable detail_refus_avec_reponses "Détail : consentement refusé (consentement_td=2) mais réponses TD renseignées quand même"


/*=========================================================================================
	II.6 - AUTRES CONTROLES DE COHERENCE (filtres/plages), base individu (TD)
===========================================================================================*/

	gen erreur_doublon_id = 0
	capture confirm variable id_quest
	if _rc==0 {
		duplicates tag id_quest, gen(doublon_id)
		replace erreur_doublon_id = (doublon_id>0)
		label variable erreur_doublon_id "Anomalie : id_quest en doublon"
	}

	gen detail_manq_age = missing(s1q02) & smq07==1 & consentement_td==1
	label variable detail_manq_age "Détail : tranche d'âge s1q02 (Q2) manquante pour une TD consentante"

	gen alerte_especes_sans_salaire = (ctl_td==1 & s2q06a==2 & missing(s2q08))
	label variable alerte_especes_sans_salaire "ALERTE : paiement en espèces seulement (s2q06a=2) mais s2q07/s2q08 non posées (condition du questionnaire s2q06a==1||3 à vérifier)"

	gen detail_manq_heures = missing(s2q01) & smq07==1 & consentement_td==1
	label variable detail_manq_heures "Détail : heures travaillées s2q01 (Q8) manquantes pour une TD consentante"

	* Q12 -> Q13 (raison si pas de contrat)
	gen detail_filtre_s2q06 = (s2q05==2 & missing(s2q06))
	label variable detail_filtre_s2q06 "Détail : pas de contrat (s2q05=2) mais raison s2q06 (Q13) non renseignée"
	gen detail_filtre_s2q06_inverse = (s2q05==1 & !missing(s2q06))
	label variable detail_filtre_s2q06_inverse "Détail : contrat écrit (s2q05=1) mais raison de non-contrat s2q06 (Q13) renseignée"

	gen alerte_nature_avec_salaire = (ctl_td==1 & s2q06a==1 & (!missing(s2q07) | !missing(s2q08)))
	label variable alerte_nature_avec_salaire "ALERTE : paiement en nature seulement (s2q06a=1) mais s2q07/s2q08 (régularité, salaire en FCFA) renseignées (condition du questionnaire s2q06a==1||3 à vérifier)"

	* Q17 -> Q18/Q19
	gen detail_filtre_s2q11 = (s2q10==2 & missing(s2q11))
	label variable detail_filtre_s2q11 "Détail : pas de jour de repos (s2q10=2) mais raison s2q11 (Q18) non renseignée"
	gen detail_filtre_s2q12 = (s2q10==2 & !missing(s2q12))
	label variable detail_filtre_s2q12 "Détail : pas de jour de repos (s2q10=2) mais s2q12 (Q19, jours payés) renseignée"

	* Q43 -> Q44
	gen detail_filtre_s3q02 = (s3q01==2 & (s3q02__1==1 | s3q02__2==1 | s3q02__3==1 | s3q02__4==1 | s3q02__5==1 | s3q02__6==1 | s3q02__7==1))
	label variable detail_filtre_s3q02 "Détail : pas d'accident (s3q01=2) mais nature d'accident s3q02 (Q44) cochée"
	gen detail_filtre_s3q02_manq = (s3q01==1 & !(s3q02__1==1 | s3q02__2==1 | s3q02__3==1 | s3q02__4==1 | s3q02__5==1 | s3q02__6==1 | s3q02__7==1))
	label variable detail_filtre_s3q02_manq "Détail : accident déclaré (s3q01=1) mais nature d'accident s3q02 (Q44) non renseignée"

	* Q45 -> Q46
	gen detail_filtre_s3q04 = (s3q03==2 & (s3q04__1==1 | s3q04__2==1 | s3q04__3==1 | s3q04__4==1 | s3q04__5==1 | s3q04__6==1 | s3q04__7==1 | s3q04__8==1))
	label variable detail_filtre_s3q04 "Détail : pas de problème de santé (s3q03=2) mais s3q04 (Q46) cochée"

	* Q68 -> Q69/Q70 (uniquement TD de sexe féminin, smq02==2)
	gen detail_filtre_grossesse = (s5q06==2 & (!missing(s5q07) | !missing(s5q08)))
	label variable detail_filtre_grossesse "Détail : jamais enceinte (s5q06=2) mais s5q07/s5q08 (Q69/Q70) renseignées"
	gen detail_manq_nb_grossesses = (s5q06==1 & missing(s5q07))
	label variable detail_manq_nb_grossesses "Détail : déjà enceinte (s5q06=1) mais nombre de grossesses s5q07 (Q69) manquant"
	* CORRECTION : la validation du questionnaire exige s5q07_autre > 5 et < 20, donc de 6 à 19
	gen detail_horsplage_grossesses = (s5q07==6 & !missing(s5q07_autre) & !inrange(s5q07_autre,6,19))
	label variable detail_horsplage_grossesses "Détail : nombre de grossesses précisé s5q07_autre (Q69, si >5) hors plage 6-19 (règle du questionnaire)"

	* Q77 -> Q78
	gen detail_filtre_s6q04 = (s6q03==2 & !missing(s6q04))
	label variable detail_filtre_s6q04 "Détail : ne connaît pas d'organisation (s6q03=2) mais s6q04 (Q78) renseignée"

	* Q83 -> Q84
	gen detail_filtre_s8q02 = (s8q01==2 & !missing(s8q02))
	label variable detail_filtre_s8q02 "Détail : jamais entendu parler d'agence (s8q01=2) mais s8q02 (Q84) renseignée"

	* Alerte : TD mineure (moins de 15 ans) d'après la tranche s1q02=1 OU l'âge du roster smq04
	gen alerte_travail_mineure = (ctl_td==1 & (s1q02==1 | (smq04<15 & !missing(smq04))))
	label variable alerte_travail_mineure "ALERTE : TD de moins de 15 ans (tranche s1q02 = 1 ou âge du roster smq04 < 15)"

	* Incohérence horaires (cas extrême)
	gen erreur_horaires = (s2q02==6 & s2q03==1)
	label variable erreur_horaires "Anomalie : commence après 8h (s2q02=6, Q9) ET termine avant 17h (s2q03=1, Q10)"

	* Lien avec la fiche ménage
	gen erreur_id_menage_manquant = (missing(id_menage) | ctl_merge_est==1)
	label variable erreur_id_menage_manquant "Anomalie : aucune fiche ménage (ESTDAO_BF) retrouvée pour ce questionnaire (interview__id introuvable) ou id_menage manquant"


/*=========================================================================================
	II.6b - CONTROLES COMPLEMENTAIRES DE LA BASE INDIVIDU (NOUVEAU)
===========================================================================================*/

	capture confirm variable sIq03
	if _rc != 0 gen str30 sIq03 = ""
	capture confirm variable sIq07
	if _rc != 0 gen str30 sIq07 = ""

	* ---- Dates de référence ----
	gen double ctl_dc    = date(substr(sIq03,1,10), "YMD")	// début de collecte du ménage (référence du questionnaire pour l'âge)
	gen double ctl_dtd01 = date(substr(td01,1,10),  "YMD")	// début de l'entretien individuel
	gen double ctl_dfin  = date(substr(sIq07,1,10), "YMD")	// fin de collecte du ménage
	replace ctl_dc = ctl_dtd01 if missing(ctl_dc)
	format ctl_dc ctl_dtd01 ctl_dfin %td
	gen double ctl_an = year(ctl_dc)

	* ---- Date de naissance reconstituée (règles du questionnaire, annexe C) ----
	gen byte ctl_anok = (!missing(smq03c) & smq03c!=9999 & smq03c>=1900 & smq03c<=ctl_an)
	gen double ctl_by = .
	gen byte ctl_bm = .
	gen byte ctl_bd = .
	gen byte ctl_casA = (ctl_anok==1 & inrange(smq03a,1,31) & inrange(smq03b,1,12))	// jour et mois connus
	gen byte ctl_casB = (ctl_anok==1 & smq03a==99 & inrange(smq03b,1,12))			// jour inconnu -> le 15
	gen byte ctl_casC = (ctl_anok==1 & smq03a==99 & smq03b==99)					// jour et mois inconnus -> 1er juillet
	replace ctl_by = smq03c if ctl_casA==1 | ctl_casB==1 | ctl_casC==1
	replace ctl_bm = smq03b if ctl_casA==1 | ctl_casB==1
	replace ctl_bd = smq03a if ctl_casA==1
	replace ctl_bd = 15 if ctl_casB==1
	replace ctl_bm = 7  if ctl_casC==1
	replace ctl_bd = 1  if ctl_casC==1
	gen double ctl_age_recalcule = ctl_an - ctl_by - (month(ctl_dc) < ctl_bm | (month(ctl_dc)==ctl_bm & day(ctl_dc) < ctl_bd)) if !missing(ctl_by)
	replace ctl_age_recalcule = smq03d if smq03c==9999 & !missing(smq03d)
	label variable ctl_age_recalcule "Age recalculé à partir de la date de naissance (règle du questionnaire)"

	gen byte erreur_age_manquant = missing(smq04)
	label variable erreur_age_manquant "Anomalie : âge smq04 manquant (date de naissance ou âge approximatif incomplet)"
	gen byte erreur_age_incoherent = (!missing(ctl_age_recalcule) & !missing(smq04) & smq04 != ctl_age_recalcule)
	label variable erreur_age_incoherent "Anomalie : âge smq04 différent de l'âge recalculé à partir de la date de naissance déclarée"

	* ---- jour_nais / mois_nais / annee_naiss : doivent suivre la règle de calcul du questionnaire ----
	* (.a = pas de valeur calculée : normal quand jour ET mois de naissance sont connus)
	gen double ctl_j_att = .
	replace ctl_j_att = smq03a if smq03a!=99 & smq03b==99 & !missing(smq03a)
	replace ctl_j_att = 1  if smq03a==99 & smq03b==99
	replace ctl_j_att = 15 if smq03a==99 & inrange(smq03b,1,12)
	gen double ctl_m_att = cond(smq03b!=99, smq03b, 7) if !missing(smq03b)
	gen double ctl_a_att = cond(smq03c==9999, ctl_an - smq03d, smq03c) if !missing(smq03c)
	gen byte ctl_j_diff = 0
	replace ctl_j_diff = 1 if !missing(jour_nais) & !missing(ctl_j_att) & jour_nais != ctl_j_att
	replace ctl_j_diff = 1 if missing(jour_nais) != missing(ctl_j_att)
	gen byte ctl_m_diff = 0
	replace ctl_m_diff = 1 if !missing(mois_nais) & !missing(ctl_m_att) & mois_nais != ctl_m_att
	replace ctl_m_diff = 1 if missing(mois_nais) != missing(ctl_m_att)
	gen byte ctl_a_diff = 0
	replace ctl_a_diff = 1 if !missing(annee_naiss) & !missing(ctl_a_att) & annee_naiss != ctl_a_att
	replace ctl_a_diff = 1 if missing(annee_naiss) != missing(ctl_a_att)
	gen byte erreur_date_imputee_regle = ctl_j_diff + ctl_m_diff + ctl_a_diff
	label variable erreur_date_imputee_regle "Anomalie : jour_nais / mois_nais / annee_naiss ne suivent pas la règle (jour inconnu->15, jour+mois inconnus->1er juillet, .a si jour et mois connus)"

	* ---- Date de naissance déclarée : validité ----
	gen byte erreur_date_impossible = 0
	replace erreur_date_impossible = 1 if inrange(smq03a,1,31) & inrange(smq03b,1,12) & missing(mdy(smq03b, smq03a, cond(ctl_anok==1, smq03c, 2000)))
	replace erreur_date_impossible = 1 if inrange(smq03a,1,31) & smq03b==99
	label variable erreur_date_impossible "Anomalie : date de naissance impossible (ex. 31 avril) ou jour connu avec mois inconnu"

	gen byte erreur_annee_naissance = 0
	replace erreur_annee_naissance = 1 if missing(smq03c)
	replace erreur_annee_naissance = 1 if !missing(smq03c) & smq03c!=9999 & !missing(ctl_an) & (smq03c<1900 | smq03c>ctl_an)
	label variable erreur_annee_naissance "Anomalie : année de naissance smq03c manquante ou hors plage (1900 à l'année de collecte, ou 9999 = NSP)"

	gen byte erreur_naissance_apres_collecte = 0
	replace erreur_naissance_apres_collecte = 1 if ctl_casA==1 & !missing(mdy(ctl_bm, ctl_bd, ctl_by)) & mdy(ctl_bm, ctl_bd, ctl_by) > ctl_dc
	label variable erreur_naissance_apres_collecte "Anomalie : date de naissance postérieure à la date de début de collecte"

	* ---- Noms du roster ----
	gen str100 ctl_nom = lower(itrim(trim(smq01)))
	gen byte erreur_nom_membre = (wordcount(ctl_nom)<2 | length(ctl_nom)<5 | regexm(ctl_nom, "[0-9]"))
	label variable erreur_nom_membre "Anomalie : nom du membre (smq01) incomplet (moins de 2 mots / 5 caractères) ou contenant un chiffre"
	duplicates tag interview__id ctl_nom, gen(ctl_dupnom)
	gen byte erreur_nom_doublon_menage = (ctl_dupnom>0 & ctl_nom!="")
	label variable erreur_nom_doublon_menage "Anomalie : même nom saisi deux fois dans le même ménage"

	* ---- Contrôles génériques : manquants / hors filtre / modalités / cases à cocher ----
	local any_s3q04 "(s3q04__1==1 | s3q04__2==1 | s3q04__3==1 | s3q04__4==1 | s3q04__5==1 | s3q04__6==1 | s3q04__7==1 | s3q04__8==1)"
	local any_s8q03 "(s8q03__1==1 | s8q03__2==1 | s8q03__3==1 | s8q03__4==1 | s8q03__5==1 | s8q03__6==1 | s8q03__7==1)"
	local fem "ctl_td==1 & smq02==2"

	global ctl_keyvars "ligne_base_questionnaire interview__key menage__id id_quest id_menage sIq01 s0q03_label s0q04"
	ctl_init

	* -- Roster (tous les membres)
	ctl_q smq02, si(1==1) codes(1 2)
	ctl_q consentement_td, si(smq07==1 | !missing(consentement_td)) codes(1 2)
	ctl_q smq04, si(!missing(smq04)) plage(0 120)
	ctl_q smq03a, si(1==1) codes(1/31 99)
	ctl_q smq03b, si(1==1) codes(1/12 99)
	ctl_q smq03d, si(smq03c==9999) plage(0 120)
	ctl_q smq04_confirm, si(smq03c!=9999 & !missing(smq03c)) codes(1 3)
	ctl_q smq05, si(smq04>=5 & !missing(smq04)) codes(1/6)
	ctl_q smq06, si(smq04>=15 & !missing(smq04)) codes(1/4)
	ctl_q smq07, si(smq04>=10 & !missing(smq04)) codes(1 2)

	gen int ctl_manq_roster = erreur_manq_oblig

	* -- Questionnaire TD (TD identifiée et consentante) : parties 1 à 9 et résultat de l'entretien
	ctl_q tdage_confirm, si(ctl_td==1 & smq03c!=9999 & !missing(smq03c)) codes(1)
	ctl_q s1q01, si(ctl_td==1)
	ctl_q s1q02, si(ctl_td==1) codes(1/4)
	ctl_q s1q03, si(ctl_td==1) codes(1/4)
	ctl_q s1q04, si(ctl_td==1) codes(1/5)
	ctl_q s1q06, si(ctl_td==1) codes(1/8)
	ctl_q s1q06_autre, si(ctl_td==1 & s1q06==8)
	ctl_multi s1q07, nb(6) si(ctl_td==1) aumoinsun
	ctl_q s1q07_autre, si(ctl_td==1 & s1q07__6==1)
	ctl_q s2q01, si(ctl_td==1) codes(1/3)
	ctl_q s2q02, si(ctl_td==1) codes(1/6)
	ctl_q s2q03, si(ctl_td==1) codes(1/6)
	ctl_q s2q04, si(ctl_td==1) codes(1/5)
	ctl_q s2q05, si(ctl_td==1) codes(1 2)
	ctl_q s2q06, si(ctl_td==1 & s2q05==2) codes(1/3)
	ctl_q s2q06_autres, si(ctl_td==1 & s2q06==3)
	ctl_q s2q06a, si(ctl_td==1) codes(1/3)
	ctl_q s2q07, si(ctl_td==1 & (s2q06a==1 | s2q06a==3)) codes(1/3)
	ctl_q s2q08, si(ctl_td==1 & (s2q06a==1 | s2q06a==3)) codes(1/5)
	ctl_q s2q09, si(ctl_td==1) codes(1/6)
	ctl_q s2q09_autre, si(ctl_td==1 & s2q09==6)
	ctl_q s2q10, si(ctl_td==1) codes(1 2)
	ctl_q s2q11, si(ctl_td==1 & s2q10==2) codes(1/3)
	ctl_q s2q11_autre, si(ctl_td==1 & s2q11==3)
	ctl_q s2q12, si(ctl_td==1 & s2q10==1) codes(1 2)
	ctl_q s2q13, si(ctl_td==1) codes(1/3)
	ctl_q s2q14, si(ctl_td==1 & s2q13==3) codes(1/3)
	ctl_q s2q14_autre, si(ctl_td==1 & s2q14==3)
	ctl_multi s2q15, nb(4) si(ctl_td==1)
	ctl_multi s2q16, nb(4) si(ctl_td==1 & (s2q15__1==1 | s2q15__2==1 | s2q15__3==1)) aumoinsun
	ctl_q s2q16_autre, si(ctl_td==1 & s2q16__4==1)
	ctl_q s2q17, si(ctl_td==1) codes(1 2)
	ctl_q s2q18, si(ctl_td==1) codes(1 2)
	ctl_q s2q19, si(ctl_td==1) codes(1 2)
	ctl_q s2q20, si(ctl_td==1) codes(1 2)
	ctl_q s2q21, si(ctl_td==1) codes(1 2)
	ctl_q s2q22, si(ctl_td==1) codes(1 2)
	ctl_q s2q23, si(ctl_td==1) codes(1 2)
	ctl_q s2q24, si(ctl_td==1) codes(1 2)
	ctl_q s2q25, si(ctl_td==1) codes(1 2)
	ctl_q s2q26, si(ctl_td==1) codes(1 2)
	ctl_q s2q27, si(ctl_td==1) codes(1 2)
	ctl_q s2q28, si(ctl_td==1) codes(1 2)
	ctl_q s2q29, si(ctl_td==1) codes(1 2)
	ctl_q s2q30, si(ctl_td==1) codes(1 2)
	ctl_q s2q31, si(ctl_td==1) codes(1 2)
	ctl_q s2q32, si(ctl_td==1) codes(1 2)
	ctl_q s2q33, si(ctl_td==1) codes(1 2)
	ctl_q s2q34, si(ctl_td==1) codes(1 2)
	ctl_q s2q35, si(ctl_td==1) codes(1 2)
	ctl_q s2q22_precision, si(ctl_td==1 & s2q22==1)
	ctl_q s2q28_precision, si(ctl_td==1 & s2q28==1)
	ctl_q s3q01, si(ctl_td==1) codes(1 2)
	ctl_multi s3q02, nb(7) si(ctl_td==1 & s3q01==1) aumoinsun
	ctl_q s3q02_autre, si(ctl_td==1 & s3q02__7==1)
	ctl_q s3q03, si(ctl_td==1) codes(1 2)
	ctl_multi s3q04, nb(8) si(ctl_td==1 & s3q03==1) aumoinsun
	ctl_q s3q04_autre, si(ctl_td==1 & s3q04__8==1)
	ctl_q s3q05, si(ctl_td==1 & `any_s3q04') codes(1 2)
	ctl_q s3q06, si(ctl_td==1 & s3q05==1) codes(1/4)
	ctl_q s3q06_autre, si(ctl_td==1 & s3q06==4)
	ctl_q s3q07, si(ctl_td==1) codes(1 2)
	ctl_multi s3q08, nb(5) si(ctl_td==1 & s3q07==1) aumoinsun
	ctl_q s3q08_autre, si(ctl_td==1 & s3q08__5==1)
	ctl_q s3q09, si(ctl_td==1) codes(1 2)
	ctl_q s3q10, si(ctl_td==1 & s3q09==2) codes(1/4)
	ctl_q s3q10_autre, si(ctl_td==1 & s3q10==4)
	ctl_q s3q11, si(ctl_td==1) codes(1 2)
	ctl_q s3q12, si(ctl_td==1 & s3q11==2) codes(1 2)
	ctl_q s3q13, si(ctl_td==1) codes(1 2)
	ctl_q s3q14, si(ctl_td==1) codes(1 2)
	ctl_q s4q01, si(ctl_td==1) codes(1/4)
	ctl_q s4q02, si(ctl_td==1) codes(1/4)
	ctl_q s4q03, si(ctl_td==1) codes(1/4)
	ctl_q s4q04, si(ctl_td==1) codes(1 2)
	ctl_q s4q05, si(ctl_td==1) codes(1 2)
	ctl_q s4q06, si(ctl_td==1) codes(1 2)
	ctl_q s5q01, si(`fem') codes(1 2)
	ctl_q s5q02, si(`fem' & s5q01==2) codes(1/5)
	ctl_q s5q02_autre, si(`fem' & s5q02==5)
	ctl_q s5q03, si(`fem') codes(1/3)
	ctl_q s5q03_autre, si(`fem' & s5q03==3)
	ctl_q s5q04, si(`fem') codes(1 2)
	ctl_q s5q05, si(`fem' & s5q04==2) codes(1/5)
	ctl_q s5q05_autre, si(`fem' & s5q05==5)
	ctl_q s5q06, si(`fem') codes(1 2)
	ctl_q s5q07, si(`fem' & s5q06==1) codes(1/6)
	ctl_q s5q07_autre, si(`fem' & s5q07==6) plage(6 19)
	ctl_q s5q08, si(`fem' & s5q06==1) codes(1/3)
	ctl_q s5q08_autre, si(`fem' & s5q08==3)
	ctl_q s5q09, si(`fem') codes(1 2)
	ctl_q s5q10, si(`fem' & s5q09==2) codes(1/5)
	ctl_q s5q10_autre, si(`fem' & s5q10==5)
	ctl_q s5q11, si(`fem' & s5q06==1) codes(1 2)
	ctl_q s5q12, si(`fem' & s5q06==1) codes(1/3)
	ctl_q s6q01, si(ctl_td==1) codes(1 2)
	ctl_q s6q02, si(ctl_td==1) codes(1 2)
	ctl_q s6q03, si(ctl_td==1) codes(1 2)
	ctl_q s6q04, si(ctl_td==1 & s6q03==1) codes(1/5)
	ctl_multi s6q05, nb(5) si(ctl_td==1)
	ctl_q s6q05_autre, si(ctl_td==1 & s6q05__5==1)
	ctl_multi s6q06, nb(7) si(ctl_td==1)
	ctl_q s6q06_autre, si(ctl_td==1 & s6q06__7==1)
	ctl_q s6q07, si(ctl_td==1) codes(1 2)
	ctl_q s7q01, si(ctl_td==1)
	ctl_q s8q01, si(ctl_td==1) codes(1 2)
	ctl_q s8q02, si(ctl_td==1 & s8q01==1) codes(1 2)
	ctl_multi s8q03, nb(7) si(ctl_td==1 & s8q02==1) aumoinsun
	ctl_q s8q03_autre, si(ctl_td==1 & s8q03__7==1)
	ctl_q s8q04, si(ctl_td==1 & `any_s8q03') codes(1 2)
	ctl_multi s8q05, nb(5) si(ctl_td==1 & s8q04==2) aumoinsun
	ctl_q s8q05_autre, si(ctl_td==1 & s8q05__5==1)
	ctl_q s9q01, si(ctl_td==1) codes(1 2)
	ctl_multi s9q02, nb(6) si(ctl_td==1 & s9q01==1) aumoinsun
	ctl_q s9q02_autre, si(ctl_td==1 & s9q02__6==1)
	ctl_q s9q03, si(ctl_td==1) codes(1/3)
	ctl_q s9q04, si(ctl_td==1) codes(1 2)
	ctl_q s9q05, si(ctl_td==1) codes(1 2 3 5)
	ctl_q s9q06, si(ctl_td==1) codes(1 2)
	ctl_q s9q07, si(ctl_td==1 & s9q06==1) codes(1/6)
	ctl_q s9q07_autre, si(ctl_td==1 & s9q07==6)
	ctl_q s9q08, si(ctl_td==1 & s9q06==1) codes(1/3)
	ctl_q s9q09, si(ctl_td==1 & s9q06==1) codes(1/5)
	ctl_q s9q09_autre, si(ctl_td==1 & s9q09==5)
	ctl_q td01, si(autorisation_debut==1)
	ctl_q td02, si(!missing(consentement_td)) codes(1/6)
	ctl_q td02_autres, si(td02==6)

	gen int ctl_manq_td = erreur_manq_oblig - ctl_manq_roster
	label variable ctl_manq_td "Nb de questions TD posées mais non renseignées"

	* ---- Cohérences entre variables ----
	* tranche d'âge déclarée (s1q02) vs âge du roster (smq04)
	gen double ctl_tr_att = .
	replace ctl_tr_att = 1 if smq04<15
	replace ctl_tr_att = 2 if smq04>=15 & smq04<18
	replace ctl_tr_att = 3 if smq04>=18 & smq04<35
	replace ctl_tr_att = 4 if smq04>=35 & !missing(smq04)
	gen byte erreur_age_tranche = (ctl_td==1 & !missing(s1q02) & !missing(ctl_tr_att) & s1q02 != ctl_tr_att & !(smq04==35 & inlist(s1q02,3,4)))
	label variable erreur_age_tranche "Anomalie : tranche d'âge s1q02 (Q2) non cohérente avec l'âge du roster smq04"

	* statut matrimonial : roster (smq06) vs questionnaire TD (s1q03), mêmes codes 1-4
	gen byte erreur_matrimonial_diff = (ctl_td==1 & !missing(smq06) & !missing(s1q03) & smq06 != s1q03)
	label variable erreur_matrimonial_diff "Anomalie : statut matrimonial du roster (smq06) différent de celui du questionnaire TD (s1q03)"

	* résultat de l'entretien TD (td02=1 'complètement rempli') alors que des questions posées sont vides
	gen byte erreur_td02_complet_incoher = (ctl_td==1 & td02==1 & ctl_manq_td>0)
	label variable erreur_td02_complet_incoher "Anomalie : TD marquée 'complètement remplie' (td02=1) alors que des questions posées sont non renseignées"

	* alertes (à vérifier, non comptées dans nb_anomalies)
	gen byte alerte_niveau_etude_diff = (ctl_td==1 & inrange(smq05,1,5) & !missing(s1q04) & smq05 != s1q04)
	label variable alerte_niveau_etude_diff "ALERTE : niveau d'études du roster (smq05) différent du niveau d'éducation en français du questionnaire TD (s1q04)"
	gen byte alerte_etude_age = (((smq05==5 & smq04<${seuil_superieur_age}) | (smq05==4 & smq04<${seuil_secondaire_age})) & !missing(smq04))
	label variable alerte_etude_age "ALERTE : niveau d'études (smq05) peu plausible pour l'âge (Supérieur avant 17 ans ou Secondaire avant 12 ans, seuils modifiables)"
	gen byte alerte_td02_vs_consentement = ((consentement_td==2 & !missing(td02) & td02!=3) | (consentement_td==1 & td02==3))
	label variable alerte_td02_vs_consentement "ALERTE : résultat de l'entretien TD (td02) non cohérent avec le consentement (refus <-> 'Refusé')"
	gen byte alerte_sanction_sans_controle = (ctl_td==1 & s9q03==3 & s9q04==1)
	label variable alerte_sanction_sans_controle "ALERTE : employeur sanctionné par l'Inspection (s9q04=1) alors que la TD déclare n'avoir jamais été contrôlée (s9q03=3)"
	gen byte alerte_td01_hors_periode = (!missing(ctl_dtd01) & !missing(ctl_dc) & !missing(ctl_dfin) & (ctl_dtd01 < ctl_dc | ctl_dtd01 > ctl_dfin))
	label variable alerte_td01_hors_periode "ALERTE : date de début de l'entretien (td01) hors de la période du ménage (sIq03 à sIq07)"

	* alertes optionnelles (interrupteurs en SECTION 0bis)
	gen byte info_date_imputee = (smq03a==99 | smq03b==99 | smq03c==9999)
	label variable info_date_imputee "INFO : date de naissance imputée (jour inconnu->15, jour+mois inconnus->1er juillet, année déduite de l'âge)"
	gen byte info_smq03d_vide = (smq03c!=9999 & !missing(smq03c) & missing(smq03d))
	label variable info_smq03d_vide "INFO : année de naissance connue donc smq03d (âge approximatif) vide -- comportement normal du filtre"

	egen nb_anomalies = rowtotal(erreur_*)
	label variable nb_anomalies "Nombre total d'anomalies détectées pour le membre / la TD"
	egen nb_alertes = rowtotal(alerte_*)
	label variable nb_alertes "Nombre d'alertes (à vérifier, non comptées comme anomalies)"

	gen statut_controle = "🟢 Normal"
	replace statut_controle = "🟡 Alerte(s) à vérifier" if nb_alertes>=1
	replace statut_controle = "🟠 A surveiller" if nb_anomalies>=1 & nb_anomalies<=2
	replace statut_controle = "🔴 A corriger"    if nb_anomalies>=3
	label variable statut_controle "Statut de contrôle qualité de la TD / du membre"

	* ---- Enregistrement des listings (ordre = numéro d'onglet ; list1 à list23 = onglets historiques) ----
	global nflags 0
	addflag detail_td_hors_filtre "smq07 s1q02" "Détail : réponses TD renseignées alors que smq07 != 1 (non identifié TD)"
	addflag detail_consentement_manquant "smq07 consentement_td" "Détail : identifié TD (smq07=1) mais consentement (consentement_td) non renseigné"
	addflag detail_refus_avec_reponses "consentement_td s1q02" "Détail : consentement refusé (consentement_td=2) mais réponses TD renseignées quand même"
	addflag erreur_doublon_id "id_quest" "Anomalie : id_quest en doublon"
	addflag detail_manq_age "s1q02" "Détail : tranche d'âge s1q02 (Q2) manquante pour une TD consentante"
	addflag alerte_especes_sans_salaire "s2q06a s2q07 s2q08" "ALERTE : paiement en espèces seulement (s2q06a=2) mais s2q07/s2q08 non posées (condition du questionnaire s2q06a==1||3 à vérifier)"
	addflag detail_manq_heures "s2q01" "Détail : heures travaillées s2q01 (Q8) manquantes pour une TD consentante"
	addflag detail_filtre_s2q06 "s2q05 s2q06" "Détail : pas de contrat (s2q05=2) mais raison s2q06 (Q13) non renseignée"
	addflag detail_filtre_s2q06_inverse "s2q05 s2q06" "Détail : contrat écrit (s2q05=1) mais raison de non-contrat s2q06 (Q13) renseignée"
	addflag alerte_nature_avec_salaire "s2q06a s2q07 s2q08" "ALERTE : paiement en nature seulement (s2q06a=1) mais s2q07/s2q08 (régularité, salaire en FCFA) renseignées (condition du questionnaire s2q06a==1||3 à vérifier)"
	addflag detail_filtre_s2q11 "s2q10 s2q11" "Détail : pas de jour de repos (s2q10=2) mais raison s2q11 (Q18) non renseignée"
	addflag detail_filtre_s2q12 "s2q10 s2q12" "Détail : pas de jour de repos (s2q10=2) mais s2q12 (Q19, jours payés) renseignée"
	addflag detail_filtre_s3q02 "s3q01 s3q02__1 s3q02__2 s3q02__3 s3q02__4 s3q02__5 s3q02__6 s3q02__7" "Détail : pas d'accident (s3q01=2) mais nature d'accident s3q02 (Q44) cochée"
	addflag detail_filtre_s3q02_manq "s3q01 s3q02__1 s3q02__2 s3q02__3 s3q02__4 s3q02__5 s3q02__6 s3q02__7" "Détail : accident déclaré (s3q01=1) mais nature d'accident s3q02 (Q44) non renseignée"
	addflag detail_filtre_s3q04 "s3q03 s3q04__1 s3q04__2 s3q04__3 s3q04__4 s3q04__5 s3q04__6 s3q04__7 s3q04__8" "Détail : pas de problème de santé (s3q03=2) mais s3q04 (Q46) cochée"
	addflag detail_filtre_grossesse "s5q06 s5q07 s5q08" "Détail : jamais enceinte (s5q06=2) mais s5q07/s5q08 (Q69/Q70) renseignées"
	addflag detail_manq_nb_grossesses "s5q06 s5q07" "Détail : déjà enceinte (s5q06=1) mais nombre de grossesses s5q07 (Q69) manquant"
	addflag detail_horsplage_grossesses "s5q07 s5q07_autre" "Détail : nombre de grossesses précisé s5q07_autre (Q69, si >5) hors plage 6-19 (règle du questionnaire)"
	addflag detail_filtre_s6q04 "s6q03 s6q04" "Détail : ne connaît pas d'organisation (s6q03=2) mais s6q04 (Q78) renseignée"
	addflag detail_filtre_s8q02 "s8q01 s8q02" "Détail : jamais entendu parler d'agence (s8q01=2) mais s8q02 (Q84) renseignée"
	addflag alerte_travail_mineure "smq04 s1q02" "ALERTE : TD de moins de 15 ans (tranche s1q02 = 1 ou âge du roster smq04 < 15)"
	addflag erreur_horaires "s2q02 s2q03" "Anomalie : commence après 8h (s2q02=6, Q9) ET termine avant 17h (s2q03=1, Q10)"
	addflag erreur_id_menage_manquant "interview__id" "Anomalie : aucune fiche ménage (ESTDAO_BF) retrouvée pour ce questionnaire (interview__id introuvable) ou id_menage manquant"
	addflag erreur_manq_oblig "liste_manq_oblig" "Anomalie : nb de questions POSEES mais non renseignées (détail variable par variable dans l'onglet 'corrections terrain')"
	addflag erreur_hors_filtre "liste_hors_filtre" "Anomalie : nb de questions renseignées alors qu'elles NE DEVAIENT PAS être posées (détail dans l'onglet 'corrections terrain')"
	addflag erreur_modalite "liste_modalite" "Anomalie : nb de modalités/valeurs incorrectes (détail dans l'onglet 'corrections terrain')"
	addflag erreur_multi_aucun "liste_multi_aucun" "Anomalie : question à cases à cocher posée mais aucune option cochée Oui (détail dans l'onglet 'corrections terrain')"
	addflag erreur_age_manquant "smq03a smq03b smq03c smq03d smq04" "Anomalie : âge smq04 manquant (date de naissance ou âge approximatif incomplet)"
	addflag erreur_age_incoherent "smq03a smq03b smq03c smq03d smq04 ctl_age_recalcule" "Anomalie : âge smq04 différent de l'âge recalculé à partir de la date de naissance déclarée"
	addflag erreur_date_imputee_regle "smq03a smq03b smq03c smq03d jour_nais mois_nais annee_naiss" "Anomalie : jour_nais / mois_nais / annee_naiss ne suivent pas la règle (jour inconnu->15, jour+mois inconnus->1er juillet, .a si jour et mois connus)"
	addflag erreur_date_impossible "smq03a smq03b smq03c" "Anomalie : date de naissance impossible (ex. 31 avril) ou jour connu avec mois inconnu"
	addflag erreur_annee_naissance "smq03c smq03d" "Anomalie : année de naissance smq03c manquante ou hors plage (1900 à l'année de collecte, ou 9999 = NSP)"
	addflag erreur_naissance_apres_collecte "smq03a smq03b smq03c sIq03" "Anomalie : date de naissance postérieure à la date de début de collecte"
	addflag erreur_nom_membre "smq01" "Anomalie : nom du membre (smq01) incomplet (moins de 2 mots / 5 caractères) ou contenant un chiffre"
	addflag erreur_nom_doublon_menage "smq01" "Anomalie : même nom saisi deux fois dans le même ménage"
	addflag erreur_age_tranche "smq04 s1q02" "Anomalie : tranche d'âge s1q02 (Q2) non cohérente avec l'âge du roster smq04"
	addflag erreur_matrimonial_diff "smq04 smq06 s1q03" "Anomalie : statut matrimonial du roster (smq06) différent de celui du questionnaire TD (s1q03)"
	addflag erreur_td02_complet_incoher "td02 ctl_manq_td liste_manq_oblig" "Anomalie : TD marquée 'complètement remplie' (td02=1) alors que des questions posées sont non renseignées"
	addflag alerte_niveau_etude_diff "smq05 s1q04" "ALERTE : niveau d'études du roster (smq05) différent du niveau d'éducation en français du questionnaire TD (s1q04)"
	addflag alerte_etude_age "smq04 smq05" "ALERTE : niveau d'études (smq05) peu plausible pour l'âge (Supérieur avant 17 ans ou Secondaire avant 12 ans, seuils modifiables)"
	addflag alerte_td02_vs_consentement "consentement_td td02" "ALERTE : résultat de l'entretien TD (td02) non cohérent avec le consentement (refus <-> 'Refusé')"
	addflag alerte_sanction_sans_controle "s9q03 s9q04" "ALERTE : employeur sanctionné par l'Inspection (s9q04=1) alors que la TD déclare n'avoir jamais été contrôlée (s9q03=3)"
	addflag alerte_td01_hors_periode "td01 sIq03 sIq07" "ALERTE : date de début de l'entretien (td01) hors de la période du ménage (sIq03 à sIq07)"
	if ${lister_dates_imputees}==1 addflag info_date_imputee "smq03a smq03b smq03c smq03d jour_nais mois_nais annee_naiss" "INFO : date de naissance imputée (jour inconnu->15, jour+mois inconnus->1er juillet, année déduite de l'âge)"
	if ${lister_smq03d_vide}==1 addflag info_smq03d_vide "smq03c smq03d" "INFO : année de naissance connue donc smq03d (âge approximatif) vide -- comportement normal du filtre"

	di as text "Variables / conditions non évaluées (absentes de la base individu) : ${ctl_absentes}"

	save "$temp/base_questionnaire_avec_indicateurs.dta", replace




/*=========================================================================================
	II.7 - EXPORT DES LISTINGS D'ERREURS (BASE INDIVIDU/TD) VERS EXCEL
	1 onglet par indicateur ayant des cas ; onglet "description des erreurs" (avec la liste des
	variables concernées : nom = label) ; onglet "dictionnaire variables" (nom + label de toute la base).
===========================================================================================*/

	use "$temp/base_questionnaire_avec_indicateurs.dta", clear

	local idvars ligne_base_questionnaire interview__key menage__id id_quest id_menage nb_anomalies nb_alertes statut_controle
	foreach v in sIq01 sIq03 s0q01 s0q02 s0q03_label s0q04 s1q01p s1q05 {
		capture confirm variable `v'
		if _rc==0 local idvars `idvars' `v'
	}

	ctl_export using "$listing/listing erreurs questionnaire travailleuses domestiques.xlsx", idvars(`idvars') dico

	* ---- Graphiques (dossier "Graphiques") ----
	ctl_graphs, prefixe("TD") statut(statut_controle) anom(nb_anomalies) si(ctl_td==1) enq(sIq01) titre("TD identifiées et consentantes")


/*=========================================================================================
	II.8 - SAUVEGARDE DE LA BASE INDIVIDU (TD) APUREE
	NB : on ne garde que les TD réellement interviewées (smq07==1 & consentement_td==1)
	pour le rapprochement de la Partie III.
===========================================================================================*/

	use "$temp/base_questionnaire_avec_indicateurs.dta", clear

	keep if smq07==1 & consentement_td==1

	capture drop erreur_*
	capture drop detail_*
	capture drop alerte_*
	capture drop info_*
	capture drop liste_*
	capture drop ctl_*
	drop nb_anomalies nb_alertes statut_controle doublon_id
	save "$sortie/base_questionnaire_td_apuree.dta", replace


/*==============================================================================
================================================================================
	 PARTIE III : RAPPROCHEMENT MENAGE <-> INDIVIDU (COUVERTURE DE LA COLLECTE)
================================================================================
===============================================================================*/

	use "$sortie/base_questionnaire_td_apuree.dta", clear

	gen byte un_questionnaire = 1
	collapse (sum) nb_td_interviewees=un_questionnaire, by(interview__id)
	tempfile td_par_menage
	save `td_par_menage'

	use "$sortie/base_denombrement_apuree.dta", clear
	merge 1:1 interview__id using `td_par_menage'
	* _merge==1 : ménage dénombré, aucune TD interviewée retrouvée
	* _merge==2 : questionnaire TD reçu sans ménage de rattachement connu (interview__id introuvable côté dénombrement)
	* _merge==3 : rapprochement réussi
	* NB : "id_menage" (=idConcession) reste dans la base pour la lecture humaine
	* des listings (ci-dessous), mais ce n'est plus lui qui sert au rapprochement.

	replace nb_td_interviewees = 0 if missing(nb_td_interviewees)

	gen ecart_couverture = nb_td_interviewees - a07
	label variable ecart_couverture "Ecart : TD interviewées - TD annoncées au dénombrement (A7)"

	gen byte td_annoncee_proxy = (!missing(a07) & a07>0 & a07!=-9999)
	label variable td_annoncee_proxy "Proxy de A6 (TD annoncée) construit à partir de A7 -- a06 absente de cet export, voir I.2"

	gen anomalie_couverture = ""
	replace anomalie_couverture = "🔴 TD annoncée(s) au dénombrement mais aucun questionnaire reçu" ///
		if td_annoncee_proxy==1 & nb_td_interviewees==0
		* version originale : if a06==1 & nb_td_interviewees==0
	replace anomalie_couverture = "🟠 Plus de questionnaires reçus que de TD annoncées" ///
		if nb_td_interviewees > a07 & !missing(a07) & a07!=-9999
	replace anomalie_couverture = "🟠 Questionnaire(s) reçu(s) pour un ménage sans TD déclarée (A6=Non)" ///
		if td_annoncee_proxy==0 & nb_td_interviewees>0
		* version originale : if a06==2 & nb_td_interviewees>0
	replace anomalie_couverture = "🟢 Couverture conforme" if anomalie_couverture==""
	label variable anomalie_couverture "Diagnostic du rapprochement ménage <-> questionnaire"

	save "$sortie/base_rapprochement_menage_individu.dta", replace

	count if td_annoncee_proxy==1 & nb_td_interviewees==0
	local n1 = r(N)
	count if nb_td_interviewees > a07 & !missing(a07) & a07!=-9999
	local n2 = r(N)
	count if td_annoncee_proxy==0 & nb_td_interviewees>0
	local n3 = r(N)

	putexcel clear
	putexcel set "$listing/listing ecarts couverture menage vs questionnaire.xlsx", ///
		sheet("description des erreurs") replace
	putexcel a1="nom de la feuille" b1="description du listing contenu dans la feuille" c1="nombre de cas trouvés" d1="onglet créé ?"
	putexcel a1:d1, bold
	putexcel a2="list1" b2="TD annoncée(s) au dénombrement mais aucun questionnaire reçu" c2=`n1' d2=(cond(`n1'>0,"Oui","Non (0 cas -> pas d'onglet)"))
	putexcel a3="list2" b3="Plus de questionnaires reçus que de TD annoncées au dénombrement" c3=`n2' d3=(cond(`n2'>0,"Oui","Non (0 cas -> pas d'onglet)"))
	putexcel a4="list3" b4="Questionnaire(s) reçu(s) pour un ménage sans TD déclarée (A6=Non)" c4=`n3' d4=(cond(`n3'>0,"Oui","Non (0 cas -> pas d'onglet)"))

	preserve
		keep if td_annoncee_proxy==1 & nb_td_interviewees==0	// version originale : a06==1 (voir I.2 et remarque ci-dessus)
		keeporder id_menage s0q01 s0q02 s0q03_label s0q04 a07 nb_td_interviewees anomalie_couverture
		if `n1'>0 export excel "$listing/listing ecarts couverture menage vs questionnaire.xlsx", firstrow(variable) sheet("list1", modify)
	restore

	preserve
		keep if nb_td_interviewees > a07 & !missing(a07) & a07!=-9999
		keeporder id_menage s0q01 s0q02 s0q03_label s0q04 a07 nb_td_interviewees anomalie_couverture
		if `n2'>0 export excel "$listing/listing ecarts couverture menage vs questionnaire.xlsx", firstrow(variable) sheet("list2", modify)
	restore

	preserve
		keep if td_annoncee_proxy==0 & nb_td_interviewees>0	// version originale : a06==2 (voir I.2 et remarque ci-dessus)
		keeporder id_menage s0q01 s0q02 s0q03_label s0q04 a07 nb_td_interviewees anomalie_couverture
		if `n3'>0 export excel "$listing/listing ecarts couverture menage vs questionnaire.xlsx", firstrow(variable) sheet("list3", modify)
	restore


/*=========================================================================================
	III. RAPPROCHEMENTS COMPLEMENTAIRES ENTRE LES DEUX FICHIERS (NOUVEAU)
===========================================================================================*/

	use "$temp/base_questionnaire_avec_indicateurs.dta", clear
	gen byte ctl_un = 1
	gen byte ctl_est_td = (smq07==1)
	collapse (sum) nb_lignes_roster_menage=ctl_un nb_td_roster=ctl_est_td, by(interview__id)
	label variable nb_lignes_roster_menage "Nombre de membres du roster dans le fichier individu"
	label variable nb_td_roster "Nombre de membres identifiés TD (smq07=1) dans le fichier individu"
	tempfile roster_par_menage
	save `roster_par_menage'

	use "$sortie/base_rapprochement_menage_individu.dta", clear
	merge 1:1 interview__id using `roster_par_menage', generate(ctl_merge_roster) keep(master match)
	drop ctl_merge_roster
	replace nb_lignes_roster_menage = 0 if missing(nb_lignes_roster_menage)
	replace nb_td_roster = 0 if missing(nb_td_roster)

	gen byte erreur_calc1_vs_roster = (!missing(calc1) & nb_lignes_roster_menage>0 & calc1 != nb_td_roster)
	label variable erreur_calc1_vs_roster "Anomalie : nb d'éligibles TD du fichier ménage (calc1) différent du nb de smq07=1 du fichier individu"
	gen byte erreur_roster_deux_fichiers = (nb_lignes_roster_menage>0 & !missing(nb_noms_roster_estdao) & nb_noms_roster_estdao != nb_lignes_roster_menage)
	label variable erreur_roster_deux_fichiers "Anomalie : nb de noms du roster (fichier ménage) différent du nb de membres (fichier individu)"
	gen byte alerte_hr_vs_questionnaires = (inlist(hr,3,4) & nb_lignes_roster_menage>0)
	label variable alerte_hr_vs_questionnaires "ALERTE : ménage codé Absence/Refus (hr=3 ou 4) mais des membres existent dans le fichier individu"

	global nflags 0
	addflag erreur_calc1_vs_roster "calc1 nb_td_roster nb_lignes_roster_menage" "Anomalie : nb d'éligibles TD du fichier ménage (calc1) différent du nb de smq07=1 du fichier individu"
	addflag erreur_roster_deux_fichiers "nb_noms_roster_estdao nb_lignes_roster_menage" "Anomalie : nb de noms du roster (fichier ménage) différent du nb de membres (fichier individu)"
	addflag alerte_hr_vs_questionnaires "hr nb_lignes_roster_menage" "ALERTE : ménage codé Absence/Refus (hr=3 ou 4) mais des membres existent dans le fichier individu"

	ctl_export using "$listing/listing controles croises menage vs questionnaire.xlsx", ///
		idvars(id_menage interview__key s0q01 s0q02 s0q03_label s0q04 a07 nb_td_interviewees)

	save "$sortie/base_rapprochement_menage_individu.dta", replace


/*==============================================================================
================================================================================
	 PARTIE IV : TABLEAU DE BORD GLOBAL DE SUPERVISION
================================================================================
===============================================================================*/

	use "$sortie/base_rapprochement_menage_individu.dta", clear
	di as text _n "{hline 72}"
	di as result "   TABLEAU DE BORD GLOBAL - DENOMBREMENT ET COLLECTE TD"
	di as text "{hline 72}"

	count
	di as text "TOTAL MENAGES DENOMBRES ............................... " as result r(N)

	count if td_annoncee_proxy==1
	local nmen_td = r(N)
	di as text "MENAGES DECLARANT AU MOINS 1 TD ....................... " as result `nmen_td'

	sum a07 if a07!=-9999, meanonly
	di as text "TOTAL TD ANNONCEES AU DENOMBREMENT (A7) ............... " as result r(sum)

	use "$sortie/base_questionnaire_td_apuree.dta", clear
	count
	di as text "TOTAL QUESTIONNAIRES TD RECUS ET APURES ............... " as result r(N)

	use "$sortie/base_rapprochement_menage_individu.dta", clear
	count if anomalie_couverture=="🔴 TD annoncée(s) au dénombrement mais aucun questionnaire reçu"
	di as text "MENAGES AVEC TD ANNONCEE MAIS AUCUN QUESTIONNAIRE ..... " as result r(N)

	di as text "{hline 72}"
	tab anomalie_couverture

	di as text "{hline 72}"
	di as result "Détail par région :"
	tab s0q01 anomalie_couverture, row missing	// CORRECTION : "Région" = s0q01 (pas s0q02, qui est la Province -- voir I.2)

	di as text "{hline 72}"
	di as result "Qualité du fichier individu (tous les membres du roster) :"
	use "$temp/base_questionnaire_avec_indicateurs.dta", clear
	tab statut_controle
	capture noisily tab sIq01 statut_controle, row

	di as text "{hline 72}"
	di as result "Anomalies par enquêteur (somme de nb_anomalies) :"
	capture noisily tabstat nb_anomalies nb_alertes, by(sIq01) statistics(sum mean) columns(statistics)

	* ---- Graphique de couverture : ménages dénombrés vs questionnaires reçus ----
	use "$sortie/base_rapprochement_menage_individu.dta", clear
	gen str60 ctl_cov = ustrregexra(anomalie_couverture, "^[^ ]+ ", "")
	gen byte ctl_un = 1
	capture noisily graph hbar (sum) ctl_un, over(ctl_cov, sort(1) descending label(labsize(small))) blabel(bar) ///
		bar(1, color(navy)) title("Couverture de la collecte : ménages dénombrés vs questionnaires TD") ///
		ytitle("Nombre de ménages") graphregion(color(white))
	capture graph export "$graphiques/Couverture_1_menages_vs_questionnaires.png", replace width(1600)

	di as text "{hline 72}"
	di as result "Fin du contrôle qualité et du rapprochement. Listings détaillés dans :"
	di as text `"$listing"'
	di as text "{hline 72}"

* Fin du programme*/
