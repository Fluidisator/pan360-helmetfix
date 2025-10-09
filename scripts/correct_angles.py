#!/usr/bin/python3

import os
import pandas as pd
import argparse
from img360_transformer.batch_process import process_image
import numpy as np
import subprocess

def sample_and_align_photos(
    measurements_csv,
    photodir,
    photo_ref_name,
    record_time_ref,
    photo_ref_name_fin,
    record_time_ref_fin,
    step
):
    #Variable pour choisir l'interpolation ou l'extrapolation
    interpol = False
    if photo_ref_name_fin != "" and record_time_ref_fin != 0 :
      interpol = True

    # 1. Charger le CSV
    df = pd.read_csv(measurements_csv, header=None)
    df.columns = ["time", "imux", "imuy", "imuz"]
    # 2. Lister les fichiers photo triés alphanumériquement
    photo_files = sorted([
        f for f in os.listdir(photodir)
        if f.lower().endswith(('.jpg', '.jpeg', '.png'))
    ])

    if not photo_files:
        raise ValueError("Aucune photo trouvée dans le dossier.")

    # 3. Trouver l'index de la photo de référence
    if photo_ref_name not in photo_files:
        raise ValueError(f"La photo de référence '{photo_ref_name}' est introuvable dans le dossier.")
    photo_ref_index = photo_files.index(photo_ref_name)

    # 4. Trouver la time de référence via record_time_ref
    if record_time_ref not in df['time'].values:
        raise ValueError(f"L'index de référence {record_time_ref} est introuvable dans le fichier CSV.")

    time_ref = df.loc[df['time'] == record_time_ref, 'time'].values[0]
    # Si on souhaite interpoler les données    
    if interpol:
      # 3 bis. Trouver l'index de la photo de fin
      if photo_ref_name_fin not in photo_files:
        raise ValueError(f"La photo de référence '{photo_ref_name}' est introuvable dans le dossier.")
        photo_ref_time_fin = photo_files.index(photo_ref_name_fin)
    
        # 4 bis. Trouver le temps de référence final
        if record_time_ref_fin not in df['index'].values:
          raise ValueError(f"L'index de référence {record_index_ref} est introuvable dans le fichier CSV.")
    
        # 4 ter. Calcul du step en cas d'interpolation
        time_ref_fin = df.loc[df['index'] == record_time_ref_fin, 'time'].values[0]
        step = (time_ref_fin - time_ref) / (photo_ref_time_fin - photo_ref_index)

    # 5. Générer les temps cibles autour de time_ref
    time_min = df['time'].min()
    time_max = df['time'].max()

    times_forward = np.arange(time_ref, time_max + step, step)
    times_backward = np.arange(time_ref - step, time_min - step, -step)
    times_target = np.sort(np.concatenate([times_backward, times_forward]))

    # 6. Gestion de la latence
    # Trouver, pour chaque time_target, la valeur dans les tolerance_min/max au dessus
    df_times = np.sort(df['time'].values)
    matched_times = []
    used = set()
    tolerance_min = 8
    tolerance_max = 200

    for t in times_target:
      # indices où df_times est dans l'intervalle [t + tolerance_min, t + tolerance_max]
      candidates = df_times[(df_times > t + tolerance_min) & (df_times <= t + tolerance_max)]
      if len(candidates) > 0:
        t_match = candidates[0]  # on prend le premier au-dessus dans la fenêtre
        if t_match not in used:
          matched_times.append(t_match)
          used.add(t_match)
        else:
            matched_times.append(None)
      else:
        matched_times.append(None)

    # 7. Extraire les lignes correspondantes
    rows = []
    for t_match in matched_times:
      if t_match is not None:
        row = df.loc[df['time'] == t_match].iloc[0].copy()
      else:
        # ligne vide (toutes colonnes NaN)
        row = pd.Series({col: 0 for col in df.columns})
      rows.append(row)

      df_result = pd.DataFrame(rows).reset_index(drop=True)

    # 8. Trouver la ligne de time_ref (plus proche si nécessaire)
    if not df_result.empty:
      idx_nearest = (df_result["time"] - time_ref).abs().argmin()
      row_index_number = df_result.index[idx_nearest]
    else:
      row_index_number = None
      print("df_result est vide, aucune correspondance trouvée.")

    photo_index_number = photo_files.index(photo_ref_name)
    first_row = row_index_number - photo_index_number
    df_with_photos = []
    j = 0

    for i in range(first_row, len(df_result)):
      if j < len(photo_files):  
        row = df_result.iloc[i].copy()  
        row['photo'] = photo_files[j]
        df_with_photos.append(row)
        j = j+1

    return df_with_photos

def main():
    parser = argparse.ArgumentParser(description="Horizon correcter")

    parser.add_argument('--photodir', '-d', type=str, required=True, help="Path to the photos directory")
    parser.add_argument('--recordfile', '-r', type=str, required=True, help="Path to the WitMotion record file")
    parser.add_argument('--photoref', '-p', type=str, required=True, help="Photo reference")
    parser.add_argument('--timeref', '-i', type=int, required=True, help="Time reference number corresponding to photoref")
    parser.add_argument('--photoref_fin',  type=str, default="" , help="Final photo reference")
    parser.add_argument('--timeref_fin', type=int, default=0, help="Final record line number corresponding to photoref_fin")
    parser.add_argument('--step', '-s', type=int, default=200, help="Step between records and photos")
    parser.add_argument('--camera_x', '-x', choices=["imux", "-imux", "imuy", "-imuy", "imuz", "-imuz"], default="imux", help="IMU axe on Camera X axe")
    parser.add_argument('--camera_y', '-y', choices=["imux", "-imux", "imuy", "-imuy", "imuz", "-imuz"], default="imuy", help="IMU axe on Camera Y axe")
    parser.add_argument('--camera_z', '-z', choices=["imux", "-imux", "imuy", "-imuy", "imuz", "-imuz"], default="imuz", help="IMU axe on Camera Z axe")
    parser.add_argument('--camera_roll_axe', choices=["camera_x", "camera_y", "camera_z"], default="camera_x", help="Camera roll axe")
    parser.add_argument('--camera_pitch_axe', choices=["camera_x", "camera_y", "camera_z"], default="camera_y", help="Camera pitch axe")
    parser.add_argument('--camera_yaw_axe', choices=["camera_x", "camera_y", "camera_z"], default="camera_z", help="Camera yaw axe (currently useless)")
    parser.add_argument('--pitch_level_ref', type=int, default=0, help="pitch level reference, if not 0")
    parser.add_argument('--roll_level_ref', type=int, default=0, help="roll level reference, if not 0")
    parser.add_argument('--yaw_level_ref', type=int, default=0, help="yaw level reference, if not 0")
    parser.add_argument('--outputcsv', type=str, required=True, help="Output CSV file")
    parser.add_argument('--update_images', '-u', choices=["no", "metadatas", "jpeg"], default="no",  help="Update images with angles correction")

    args = parser.parse_args()

    photodir = args.photodir
    measurements_csv = args.recordfile
    photo_ref_name = args.photoref
    record_time_ref = args.timeref
    photo_ref_name_fin = args.photoref_fin
    record_time_ref_fin = args.timeref_fin
    step = args.step
    camera_roll_axe = args.camera_roll_axe
    camera_pitch_axe = args.camera_pitch_axe
    output_csv = args.outputcsv
    update_images = args.update_images
    
    results = sample_and_align_photos(measurements_csv,photodir,photo_ref_name,record_time_ref,photo_ref_name_fin,record_time_ref_fin,step)
    csv = []
    for result in results:
      row = result
      get_imu_val = lambda arg: -row[arg[1:]] if arg.startswith("-") else row[arg]
      camera_axes = {
       "camera_x": get_imu_val(args.camera_x),
       "camera_y": get_imu_val(args.camera_y),
       "camera_z": get_imu_val(args.camera_z),
      }
      roll = camera_axes.get(args.camera_roll_axe)
      pitch = camera_axes.get(args.camera_pitch_axe)

      row["roll_corrected"]  = round(roll  - args.roll_level_ref,2)
      row["pitch_corrected"] = round(pitch - args.pitch_level_ref,2)

      if update_images == "jpeg":
        row["roll_corrected"] = -row["roll_corrected"];
        row["pitch_corrected"] = -row["pitch_corrected"];
        print("process image" + photodir + '/' + row['photo'] + "roll:"+str(row["roll_corrected"])+",pitch:"+str(round(row["pitch_corrected"])))
        process_image(photodir + '/' + row['photo'], round(row["pitch_corrected"]), round(row["roll_corrected"]), 0)
      elif update_images == "metadatas":
        print("update exifs for" + photodir + '/' + row['photo'] + " roll:"+str(row["roll_corrected"])+",pitch:"+str(round(row["pitch_corrected"])))
        subprocess.run([
          "exiftool",
          "-overwrite_original",
          f"-XMP-GPano:PosePitchDegrees={row['pitch_corrected']}",
          f"-XMP-GPano:PoseRollDegrees={row['roll_corrected']}",
          photodir + '/' + row['photo']
        ], check=True) 

      csv.append(row)

    df_out = pd.DataFrame(csv)
    df_out.to_csv(output_csv, index=False)
    print(f"Fichier '{output_csv}' généré avec {len(df_out)} lignes.")

if __name__ == "__main__":
    main()
