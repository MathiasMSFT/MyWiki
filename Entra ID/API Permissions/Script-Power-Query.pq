let
    // Chemin du CSV (modifie si nécessaire)
    FilePath = "C:\GitHub\MathiasMSFT\MyWiki\Entra ID\API Permissions\GraphAppInventory.csv",

    // 1) Charger le CSV
    Source = Csv.Document(
        File.Contents(FilePath),
        [Delimiter = ",", Encoding = 65001, QuoteStyle = QuoteStyle.Csv]
    ),
    PromotedHeaders = Table.PromoteHeaders(Source, [PromoteAllScalars = true]),

    // 2) Typage des colonnes principales (adapter si ton entête diffère)
    ChangedType = Table.TransformColumnTypes(PromotedHeaders, {
        {"Application Name", type text},
        {"ApplicationId", type text},
        {"IsBuiltIn", type text},
        {"Publisher", type text},
        {"Owned by org", type text},
        {"Verified", type text},
        {"Homepage", type text},
        {"SP name", type text},
        {"ObjectId", type text},
        {"Type", type text},
        {"Created on", type datetime},
        {"Enabled", type text},
        {"Owners", type text},
        {"Member of groups", type text},
        {"Member of roles", type text},
        {"PasswordCreds", type text},
        {"KeyCreds", type text},
        {"TokenKey", type text},
        {"Permissions application", type text},
        {"Authorized By application", type text},
        {"Last modified application", type datetime},
        {"Permissions delegate", type text},
        {"Authorized By delegate", type text},
        {"Valid until delegate", type datetime}
    }),

    // 3) Trim global pour enlever espaces parasites sur TEXTE uniquement
    TrimmedText = Table.TransformColumns(ChangedType,
        List.Transform(
            {"Application Name","ApplicationId","IsBuiltIn","Publisher","Owned by org","Verified","Homepage","SP name","ObjectId","Type","Enabled","Owners","Member of groups","Member of roles","PasswordCreds","KeyCreds","TokenKey","Permissions application","Authorized By application","Permissions delegate","Authorized By delegate"},
            (cn) => {cn, each if _ = null then null else Text.Trim(Text.From(_)), type text}
        )
    ),

    // 4) Fonctions utilitaires pour construire une clé robuste
    ToTextOrEmpty = (v as any) as text => if v = null then "" else Text.From(v),
    DateTimeToTextOrEmpty = (v as any) as text => if v = null then "" else DateTime.ToText(v, "yyyy-MM-dd HH:mm:ss"),

    // 5) Clé composite d'événement (évite le surcomptage après les splits)
    AddedEventCompositeKey = Table.AddColumn(TrimmedText, "EventCompositeKey", each
        Text.Combine({
            ToTextOrEmpty([ApplicationId]),
            DateTimeToTextOrEmpty([Created on]),
            DateTimeToTextOrEmpty([Last modified application]),
            DateTimeToTextOrEmpty([Valid until delegate])
        }, "|"), type text
    ),

    // -----------------------------
    // BRANCHE APPLICATION PERMS → lignes
    // -----------------------------
    // 6) Transformer la colonne "Permissions (application)" en LISTE (split par virgule, gestion quotes/null)
    SplitToList_App = Table.TransformColumns(AddedEventCompositeKey,
        { "Permissions application",
          each
            let
                txt    = _,
                clean  = if txt = null then "" else Text.Trim(Text.Replace(txt, """", "")),
                parts  = if clean = "" then {} else List.Transform(Text.Split(clean, ","), each Text.Trim(_))
            in
                parts,
          type list
        }
    ),

    // 7) Développer la liste en LIGNES
    ExpandRows_App = Table.ExpandListColumn(SplitToList_App, "Permissions application"),

    // 8) Nettoyer + filtrer les vides
    Clean_App = Table.TransformColumns(ExpandRows_App, {{"Permissions application", each if _ = null then "" else Text.Trim(_), type text}}),
    NonEmpty_App = Table.SelectRows(Clean_App, each [Permissions application] <> ""),

    // 9) Sélectionner/renommer les colonnes pertinentes
    Select_App = Table.SelectColumns(NonEmpty_App, {
        "EventCompositeKey", "ApplicationId", "Application Name", "Publisher", "SP name", "ObjectId", "Type",
        "Created on", "Enabled", "Permissions application", "Authorized By application", "Last modified application"
    }),
    Rename_App = Table.RenameColumns(Select_App, {
        {"Permissions application", "Permission"},
        {"Authorized By application", "AuthorizedBy"},
        {"Last modified application", "ActivityDate"}
    }),
    Type_App = Table.TransformColumnTypes(Rename_App, {
        {"Permission", type text},
        {"AuthorizedBy", type text},
        {"ActivityDate", type datetime}
    }),
    AddType_App = Table.AddColumn(Type_App, "PermissionType", each "Application", type text),

    // -----------------------------
    // BRANCHE DELEGATED PERMS → lignes
    // -----------------------------
    SplitToList_Del = Table.TransformColumns(AddedEventCompositeKey,
        { "Permissions delegate",
          each
            let
                txt    = _,
                clean  = if txt = null then "" else Text.Trim(Text.Replace(txt, """", "")),
                parts  = if clean = "" then {} else List.Transform(Text.Split(clean, ","), each Text.Trim(_))
            in
                parts,
          type list
        }
    ),
    ExpandRows_Del = Table.ExpandListColumn(SplitToList_Del, "Permissions delegate"),
    Clean_Del = Table.TransformColumns(ExpandRows_Del, {{"Permissions delegate", each if _ = null then "" else Text.Trim(_), type text}}),
    NonEmpty_Del = Table.SelectRows(Clean_Del, each [Permissions delegate] <> ""),
    Select_Del = Table.SelectColumns(NonEmpty_Del, {
        "EventCompositeKey", "ApplicationId", "Application Name", "Publisher", "SP name", "ObjectId", "Type",
        "Created on", "Enabled", "Permissions delegate", "Authorized By delegate", "Valid until delegate"
    }),
    Rename_Del = Table.RenameColumns(Select_Del, {
        {"Permissions delegate", "Permission"},
        {"Authorized By delegate", "AuthorizedBy"},
        {"Valid until delegate", "ActivityDate"}
    }),
    Type_Del = Table.TransformColumnTypes(Rename_Del, {
        {"Permission", type text},
        {"AuthorizedBy", type text},
        {"ActivityDate", type datetime}
    }),
    AddType_Del = Table.AddColumn(Type_Del, "PermissionType", each "Delegated", type text),

    // 10) UNION des deux branches en table finale
    FactConsentEvents = Table.Combine({AddType_App, AddType_Del}),

    // 11) Flag de risque (modifiable facilement)
    RiskPatterns = {"DIRECTORY.READWRITE.ALL", "APPROLEASSIGNMENT.READWRITE.ALL", "DIRECTORY.ACCESSASUSER.ALL"},
    AddRisk = Table.AddColumn(FactConsentEvents, "RiskLevel", each
        let p = Text.Upper([Permission])
        in if List.AnyTrue(List.Transform(RiskPatterns, (pat) => Text.Contains(p, pat))) then "High" else "Normal",
        type text
    ),

    // 12) Typage final & colonnes ordonnées
    FinalTyped = Table.TransformColumnTypes(AddRisk, {
        {"Application Name", type text},
        {"ApplicationId", type text},
        {"Publisher", type text},
        {"SP name", type text},
        {"ObjectId", type text},
        {"Type", type text},
        {"Created on", type datetime},
        {"Enabled", type text},
        {"AuthorizedBy", type text},
        {"Permission", type text},
        {"PermissionType", type text},
        {"ActivityDate", type datetime},
        {"RiskLevel", type text},
        {"EventCompositeKey", type text}
    }),
    Final = Table.ReorderColumns(FinalTyped, {
        "ActivityDate", "Created on", "Application Name", "ApplicationId", "Publisher", "SP name",
        "ObjectId", "Type", "Enabled", "PermissionType", "Permission", "AuthorizedBy", "RiskLevel", "EventCompositeKey"
    })
in
    Final