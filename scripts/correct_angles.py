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
    record_index_ref,
    step
):
    # On prend l'enregistrement suivant pour palier à la latence
    record_index_ref = record_index_ref + 1

    # 1. Charger le CSV
    df = pd.read_csv(measurements_csv)
    df.columns = ["time", "index", "pitch", "roll", "yaw"]

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

    # 4. Trouver la time de référence via record_index_ref
    if record_index_ref not in df['index'].values:
        raise ValueError(f"L'index de référence {record_index_ref} est introuvable dans le fichier CSV.")

    time_ref = df.loc[df['index'] == record_index_ref, 'time'].values[0]

    # 5. Générer les temps cibles autour de time_ref
    time_min = df['time'].min()
    time_max = df['time'].max()

    times_forward = np.arange(time_ref, time_max + step, step)
    times_backward = np.arange(time_ref - step, time_min - step, -step)
    times_target = np.sort(np.concatenate([times_backward, times_forward]))

    # 6. Trouver les times les plus proches dans le CSV
    df_times = df['time'].values
    matched_times = []
    used = set()

    for t in times_target:
        t_nearest = df_times[np.abs(df_times - t).argmin()]
        if t_nearest not in used:
            matched_times.append(t_nearest)
            used.add(t_nearest)

    # 7. Extraire les lignes correspondantes
    df_result = df[df['time'].isin(matched_times)].copy().sort_values('time').reset_index(drop=True)
    row_index_number = df_result.index[df_result["index"] == record_index_ref].tolist()[0]
    photo_index_number = photo_files.index(photo_ref_name) 
    first_row = row_index_number - photo_index_number
    df_with_photos = []
    j = 0
    for i in range(first_row, len(df_result)):
      if j < len(photo_files) - 1:  
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
    parser.add_argument('--indexref', '-i', type=int, required=True, help="Record line number corresponding to photoref")
    parser.add_argument('--step', '-s', type=int, default=20, help="Step between records and photos")
    parser.add_argument('--pitch_level_ref', type=int, default=0, help="pitch level reference")
    parser.add_argument('--roll_level_ref', type=int, default=0, help="roll level reference")
    parser.add_argument('--yaw_level_ref', type=int, default=0, help="yaw level reference")
    parser.add_argument('--outputcsv', type=str, required=True, help="Output CSV file")
    parser.add_argument('--update_images', '-u', choices=["no", "metadatas", "jpeg"], default="no",  help="Update images with angles correction")

    args = parser.parse_args()

    photodir = args.photodir
    photo_ref_name = args.photoref
    record_index_ref = args.indexref
    step = args.step
    measurements_csv = args.recordfile
    output_csv = args.outputcsv
    update_images = args.update_images

    results = sample_and_align_photos(measurements_csv,photodir,photo_ref_name,record_index_ref,step)
    csv = []
    for result in results:
      row = result
      row["pitch_corrected"] = round(result['pitch'] - args.pitch_level_ref)
      row["roll_corrected"]  = round(result['roll']  - args.roll_level_ref)

      if update_images == "jpeg":
        row["roll_corrected"] = -row["roll_corrected"];
        row["pitch_corrected"] = -row["pitch_corrected"];
        print("process image" + photodir + '/' + row['photo'] + "roll:"+str(row["roll_corrected"])+",pitch:"+str(round(row["pitch_corrected"])))
        process_image(photodir + '/' + row['photo'], round(row["pitch_corrected"]), round(row["roll_corrected"]), 0)
      elif update_images == "metadatas":
        print("update exifs for" + photodir + '/' + row['photo'] + "roll:"+str(row["roll_corrected"])+",pitch:"+str(round(row["pitch_corrected"])))
        subprocess.run([
          "exiftool",
          "-overwrite_original",
          f"-XMP-GPano:PosePitchDegrees={round(row['pitch_corrected'])}",
          f"-XMP-GPano:PoseRollDegrees={round(row['roll_corrected'])}",
          photodir + '/' + row['photo']
        ], check=True) 

      csv.append(row)

    df_out = pd.DataFrame(csv)
    df_out.to_csv(output_csv, index=False)
    print(f"Fichier '{output_csv}' généré avec {len(df_out)} lignes.")

if __name__ == "__main__":
    main()
